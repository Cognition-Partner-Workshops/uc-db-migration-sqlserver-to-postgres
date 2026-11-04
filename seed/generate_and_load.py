"""Deterministic synthetic P&C insurance data for the legacy SQL Server estate.

Everything is fake: names and addresses come from Faker (EU locales), IBANs are
random digits behind a country prefix, e-mail domains are example.* and every
company name is invented. A fixed seed makes every run byte-for-byte identical.

Volumes: ~2,000 policyholders, 5,000 policies, ~20,000 premium payments,
1,500 claims. A block of hand-written edge rows comes first (mixed-case codes,
half-cent amounts, NULL vs empty strings, 29 February, month-end dates,
accented names, ties on latest timestamps).

Usage: python seed/generate_and_load.py [--dry-run]
"""

from __future__ import annotations

import argparse
import calendar
import random
import sys
import uuid
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from decimal import ROUND_DOWN, Decimal
from pathlib import Path

from faker import Faker

sys.path.insert(0, str(Path(__file__).resolve().parent))
from db import mssql_connect  # noqa: E402

SEED = 20261104
AS_OF = date(2026, 10, 31)
N_POLICYHOLDERS = 2000
N_POLICIES = 5000
N_CLAIMS = 1500
N_BROKERS = 40
CENT = Decimal("0.01")
BP = Decimal("0.0001")

COUNTRIES = [
    # code, name, currency, eu, premium tax
    ("AT", "Österreich", "EUR", 1, "0.1100"),
    ("BE", "België / Belgique", "EUR", 1, "0.0925"),
    ("CH", "Schweiz", "CHF", 0, "0.0500"),
    ("DE", "Deutschland", "EUR", 1, "0.1900"),
    ("ES", "España", "EUR", 1, "0.0800"),
    ("FR", "France", "EUR", 1, "0.0900"),
    ("IE", "Éire / Ireland", "EUR", 1, "0.0300"),
    ("IT", "Italia", "EUR", 1, "0.2125"),
    ("NL", "Nederland", "EUR", 1, "0.2100"),
    ("PL", "Polska", "PLN", 1, "0.0000"),
    ("PT", "Portugal", "EUR", 1, "0.0900"),
]
COUNTRY_LOCALE = {
    "AT": "de_AT", "BE": "nl_BE", "CH": "de_CH", "DE": "de_DE", "ES": "es_ES", "FR": "fr_FR",
    "IE": "en_IE", "IT": "it_IT", "NL": "nl_NL", "PL": "pl_PL", "PT": "pt_PT",
}
COUNTRY_WEIGHTS = [6, 5, 3, 25, 12, 15, 4, 12, 10, 5, 3]

PRODUCTS = [
    # code, name, line of business, base rate (on sum insured), minimum premium
    ("MOTOR-PRIV", "Private motor", "MOTOR", "0.025000", "180.0000"),
    ("MOTOR-FLEET", "Small fleet motor", "MOTOR", "0.021000", "650.0000"),
    ("HOME-STD", "Home contents standard", "HOME", "0.001800", "95.0000"),
    ("HOME-PLUS", "Home buildings and contents", "HOME", "0.001200", "240.0000"),
    ("TRAVEL-ANN", "Annual multi-trip travel", "TRAVEL", "0.009000", "45.0000"),
    ("LIAB-PERS", "Personal liability", "LIABILITY", "0.000045", "39.9900"),
    ("Pet-Std", "Pet health standard", "PET", "0.085000", "120.0000"),
    ("SME-PROP", "SME property package", "COMMERCIAL", "0.002400", "900.0000"),
]
SUM_INSURED_RANGE = {
    "MOTOR": (8000, 60000), "HOME": (40000, 600000), "TRAVEL": (3000, 15000),
    "LIABILITY": (1000000, 5000000), "PET": (1500, 6000), "COMMERCIAL": (250000, 2500000),
}
COVERAGES = {
    "MOTOR": ["TPL", "FIRE", "THEFT", "GLASS", "ASSIST"],
    "HOME": ["FIRE", "THEFT", "GLASS", "FLOOD"],
    "TRAVEL": ["ASSIST", "THEFT"],
    "LIABILITY": ["TPL"],
    "PET": ["ASSIST"],
    "COMMERCIAL": ["FIRE", "FLOOD", "THEFT", "TPL"],
}
CAUSES = ["WATER", "FIRE", "THEFT", "COLLISION", "GLASS", "STORM", "LIABILITY"]


def trunc4(value: Decimal) -> Decimal:
    """MONEY arithmetic keeps 4 decimals by truncation."""
    return value.quantize(BP, rounding=ROUND_DOWN)


def add_months(d: date, months: int) -> date:
    month = d.month - 1 + months
    year = d.year + month // 12
    month = month % 12 + 1
    return date(year, month, min(d.day, calendar.monthrange(year, month)[1]))


def eomonth(d: date) -> date:
    return date(d.year, d.month, calendar.monthrange(d.year, d.month)[1])


def add_year_minus_day(d: date) -> date:
    return add_months(d, 12) - timedelta(days=1)


@dataclass
class Policy:
    policy_id: int
    policy_number: str
    policyholder_id: int
    broker_id: int | None
    product_idx: int
    status: str
    inception: date
    frequency: int
    annual_premium: Decimal
    sum_insured: Decimal


class Generator:
    def __init__(self) -> None:
        self.rng = random.Random(SEED)
        Faker.seed(SEED)
        self.fakers = {c: Faker(loc) for c, loc in COUNTRY_LOCALE.items()}
        for i, f in enumerate(self.fakers.values()):
            f.seed_instance(SEED + i)
        self.tables: dict[str, list[tuple]] = defaultdict(list)
        self.policies: list[Policy] = []
        self.holder_country: dict[int, str] = {}
        self.holder_dob: dict[int, date] = {}

    # -- helpers -------------------------------------------------------------
    def uid(self) -> str:
        return str(uuid.UUID(int=self.rng.getrandbits(128), version=4))

    def iban(self, country: str) -> str:
        digits = "".join(self.rng.choice("0123456789") for _ in range(18))
        return f"{country}{self.rng.randint(10, 99)}{digits}"

    def ts(self, d: date, hour_lo: int = 7, hour_hi: int = 20) -> datetime:
        return datetime(d.year, d.month, d.day, self.rng.randint(hour_lo, hour_hi), self.rng.randint(0, 59),
                        self.rng.randint(0, 59), self.rng.randrange(0, 1000) * 1000)

    @staticmethod
    def cet_offset(d: date) -> str:
        # Simplified EU summer time: last Sunday of March to last Sunday of October.
        def last_sunday(year: int, month: int) -> date:
            last = eomonth(date(year, month, 1))
            return last - timedelta(days=(last.weekday() + 1) % 7)

        return "+02:00" if last_sunday(d.year, 3) <= d < last_sunday(d.year, 10) else "+01:00"

    def dto(self, dt: datetime) -> str:
        return dt.strftime("%Y-%m-%d %H:%M:%S.") + f"{dt.microsecond // 1000:03d} " + self.cet_offset(dt.date())

    # -- reference data ----------------------------------------------------------
    def reference(self) -> None:
        for code, name, cur, eu, tax in COUNTRIES:
            self.tables["ref.country"].append((code, name, cur, eu, Decimal(tax)))
        for i, (code, name, lob, rate, minp) in enumerate(PRODUCTS, start=1):
            self.tables["ref.product"].append((i, code, name, lob, Decimal(rate), Decimal(minp), 1))

    def brokers(self) -> None:
        suffix = {"DE": "GmbH", "AT": "GmbH", "CH": "AG", "FR": "SARL", "ES": "S.L.", "IT": "S.r.l.",
                  "NL": "B.V.", "BE": "BV", "IE": "Ltd", "PL": "Sp. z o.o.", "PT": "Lda"}
        for i in range(1, N_BROKERS + 1):
            country = self.rng.choices([c[0] for c in COUNTRIES], COUNTRY_WEIGHTS)[0]
            fk = self.fakers[country]
            code = f"BRK-{i:04d}"
            if i in (7, 23):
                code = code.title()  # Brk-0007: legacy screens accepted any case
            name = f"{fk.last_name()} & {fk.last_name()} Assekuranz {suffix[country]}"
            email = f"office{i:02d}@broker{i:02d}.example.com"
            if i % 9 == 0:
                email = None
            elif i == 31:
                email = ""
            created = datetime(2018, 1, 1) + timedelta(days=self.rng.randint(0, 1500), seconds=self.rng.randint(0, 86399))
            pct = Decimal(self.rng.choice(["10.00", "12.50", "15.00"]))
            active = 0 if i == 40 else 1
            self.tables["dbo.broker"].append((i, code, name, country, pct, email, active, created))

    # -- policyholders -----------------------------------------------------------
    def policyholders(self) -> None:
        edge = [
            # first, middle, last, dob, email, country
            ("Zoë", None, "Ångström", date(2000, 2, 29), "Zoe.Angstrom@example.com", "IE"),
            ("Łukasz", "", "Wójcik", date(1996, 2, 29), "LUKASZ.WOJCIK@example.org", "PL"),
            ("François", "Marie", "Lefèvre", date(1958, 12, 31), "francois.lefevre@example.fr", "FR"),
            ("José", None, "Muñoz-Peña", date(2003, 1, 31), None, "ES"),
            ("Jürgen", " ", "Größe", date(1949, 6, 30), "", "DE"),
            ("Ægir", None, "Østergård", date(1988, 3, 31), "aegir@example.com", "NL"),
            ("Chloé", "Anaïs", "D'Aubigné", date(2007, 8, 31), "chloe.daubigne@example.be", "BE"),
            ("Ines", None, "Šimić", date(1975, 2, 28), "ines.simic@example.at", "AT"),
        ]
        hid = 0
        for first, middle, last, dob, email, country in edge:
            hid += 1
            self._holder(hid, first, middle, last, dob, email, country)
        while hid < N_POLICYHOLDERS:
            hid += 1
            country = self.rng.choices([c[0] for c in COUNTRIES], COUNTRY_WEIGHTS)[0]
            fk = self.fakers[country]
            first, last = fk.first_name(), fk.last_name()
            r = self.rng.random()
            middle = fk.first_name() if r < 0.15 else ("" if r < 0.20 else None)
            dob = date(1940, 1, 1) + timedelta(days=self.rng.randint(0, 365 * 66))
            r = self.rng.random()
            if r < 0.08:
                email = None
            elif r < 0.10:
                email = ""
            else:
                local = f"{first}.{last}{hid}".replace(" ", "").replace("'", "")
                local = local.encode("ascii", "ignore").decode() or f"holder{hid}"
                email = f"{local}@example.{self.rng.choice(['com', 'org', 'net'])}"
                if self.rng.random() < 0.3:
                    email = email.lower()
            self._holder(hid, first, middle, last, dob, email, country)

    def _holder(self, hid, first, middle, last, dob, email, country) -> None:
        fk = self.fakers[country]
        phone = None if self.rng.random() < 0.1 else f"+{self.rng.randint(30, 49)} {self.rng.randint(100, 999)} {self.rng.randint(1000000, 9999999)}"
        created = datetime(2019, 1, 1) + timedelta(days=self.rng.randint(0, 2400), seconds=self.rng.randint(0, 86399),
                                                   microseconds=self.rng.randrange(0, 1000) * 1000)
        address = fk.street_address().replace("\n", ", ")[:200]
        postcode = fk.postcode()[:12]
        city = fk.city()[:100]
        self.tables["dbo.policyholder"].append((
            hid, self.uid(), first, middle, last, dob, email, phone, self.iban(country),
            address, postcode, city, country, self.dto(created),
        ))
        self.holder_country[hid] = country
        self.holder_dob[hid] = dob

    # -- policies ---------------------------------------------------------------
    def premium_for(self, product_idx: int, sum_insured: Decimal) -> Decimal:
        _, _, _, rate, minp = PRODUCTS[product_idx]
        prem = trunc4(sum_insured * Decimal(rate) * Decimal(self.rng.randint(85, 125)) / 100)
        prem = max(prem, Decimal(minp))
        # half-cent and 4-dp amounts are common after legacy pro-rata adjustments
        r = self.rng.random()
        if r < 0.15:
            prem = prem.quantize(CENT, rounding=ROUND_DOWN) + Decimal("0.0050")
        elif r < 0.70:
            prem = prem.quantize(CENT, rounding=ROUND_DOWN)
        return prem

    def policies_and_versions(self) -> None:
        lob_by_idx = [p[2] for p in PRODUCTS]
        edge_inceptions = [date(2024, 2, 29), date(2025, 1, 31), date(2023, 3, 31), date(2025, 8, 31),
                           date(2026, 1, 31), date(2024, 11, 30), date(2025, 12, 31), date(2023, 4, 30)]
        for pid in range(1, N_POLICIES + 1):
            if pid <= len(edge_inceptions):
                inception = edge_inceptions[pid - 1]
                status = "ACTIVE" if add_year_minus_day(inception) >= AS_OF else "EXPIRED"
            else:
                inception = date(2021, 1, 1) + timedelta(days=self.rng.randint(0, (date(2026, 9, 30) - date(2021, 1, 1)).days))
                if self.rng.random() < 0.05:
                    inception = eomonth(inception)
                expiry = add_year_minus_day(inception)
                r = self.rng.random()
                if r < 0.05:
                    status = "QUOTE"
                elif r < 0.12:
                    status = "CANCELLED"
                elif r < 0.20:
                    status = "LAPSED"
                else:
                    status = "ACTIVE" if expiry >= AS_OF else "EXPIRED"
            holder = pid if pid <= N_POLICYHOLDERS else self.rng.randint(1, N_POLICYHOLDERS)
            product_idx = self.rng.choices(range(len(PRODUCTS)), [24, 4, 20, 12, 10, 12, 10, 8])[0]
            lo, hi = SUM_INSURED_RANGE[lob_by_idx[product_idx]]
            sum_insured = Decimal(self.rng.randrange(lo, hi, 500))
            broker = None if self.rng.random() < 0.3 else self.rng.randint(1, N_BROKERS - 1)
            freq = self.rng.choices([1, 2, 4, 12], [30, 20, 25, 25])[0]
            prem = self.premium_for(product_idx, sum_insured)
            pol = Policy(pid, f"P{100000 + pid:09d}", holder, broker, product_idx, status, inception, freq, prem, sum_insured)
            self.versions(pol)
            self.policies.append(pol)
            created = self.ts(inception - timedelta(days=self.rng.randint(1, 30)))
            updated = None if status in ("ACTIVE", "QUOTE") and self.rng.random() < 0.7 else self.ts(min(AS_OF, inception + timedelta(days=200)))
            self.tables["dbo.policy"].append((
                pid, pol.policy_number, holder, broker, product_idx + 1, status, inception,
                add_year_minus_day(inception), freq, pol.annual_premium, "EUR", created, updated,
            ))
            self.coverages(pol)

    def versions(self, pol: Policy) -> None:
        n = self.rng.choices([1, 2, 3], [70, 22, 8])[0]
        if pol.policy_id in (1, 2, 3):
            n = 3
        eff = pol.inception
        sum_insured, prem = pol.sum_insured, pol.annual_premium
        created = self.ts(pol.inception - timedelta(days=3))
        rows = []
        for v in range(1, n + 1):
            if v > 1:
                # policies 1-3: version 3 is a same-day correction of version 2
                same_day = pol.policy_id in (1, 2, 3) and v == 3
                if not same_day:
                    eff = eff + timedelta(days=self.rng.randint(20, 120))
                    created = self.ts(min(eff, AS_OF))
                sum_insured = (sum_insured * Decimal(self.rng.randint(95, 120)) / 100).quantize(Decimal("1"))
                prem = self.premium_for(pol.product_idx, sum_insured)
            rows.append([pol.policy_id, v, eff, None, sum_insured, prem,
                         "New business" if v == 1 else self.rng.choice(["Sum insured change", "Address change", "Correction", None]),
                         created])
        for i in range(len(rows) - 1):
            nxt = rows[i + 1][2]
            rows[i][3] = nxt - timedelta(days=1) if nxt > rows[i][2] else rows[i][2]
        for r in rows:
            self.tables["dbo.policy_version"].append(tuple(r))
        pol.sum_insured, pol.annual_premium = sum_insured, prem

    def coverages(self, pol: Policy) -> None:
        codes = COVERAGES[PRODUCTS[pol.product_idx][2]]
        chosen = [codes[0]] + [c for c in codes[1:] if self.rng.random() < 0.6]
        share_left = Decimal("1.0000")
        for i, code in enumerate(chosen):
            if pol.policy_id % 97 == 0:
                code = code.lower()
            elif pol.policy_id % 89 == 0:
                code = code.title()
            share = share_left if i == len(chosen) - 1 else (share_left / 2).quantize(BP)
            share_left -= share
            limit = (pol.sum_insured * Decimal(self.rng.choice([25, 50, 100])) / 100).quantize(BP)
            deductible = Decimal(self.rng.choice(["0", "100", "150", "250", "500", "99.995"]))
            self.tables["dbo.coverage"].append((pol.policy_id, code, limit, deductible, share))

    # -- premiums ---------------------------------------------------------------
    def schedules_and_payments(self) -> None:
        sid = 0
        for pol in self.policies:
            if pol.status == "QUOTE":
                continue
            inst = trunc4(pol.annual_premium / pol.frequency)
            step = 12 // pol.frequency
            month_end = pol.inception == eomonth(pol.inception)
            stop_paying = None
            if pol.status in ("LAPSED", "CANCELLED"):
                stop_paying = self.rng.randint(1, pol.frequency)
            for n in range(1, pol.frequency + 1):
                sid += 1
                due = add_months(pol.inception, (n - 1) * step)
                if month_end:
                    due = eomonth(due)
                amount = pol.annual_premium - inst * (pol.frequency - 1) if n == pol.frequency else inst
                paid = Decimal("0")
                status = "DUE"
                if stop_paying is not None and n > stop_paying:
                    status = "CANCELLED"
                elif due <= AS_OF:
                    r = self.rng.random()
                    if r < 0.92 or (stop_paying is None and pol.status == "EXPIRED" and r < 0.995):
                        paid, status = amount, "PAID"
                        self._payment(pol, sid, due, amount)
                    elif r < 0.95:
                        paid = (amount / 2).quantize(CENT)
                        self._payment(pol, sid, due, paid)
                        status = "OVERDUE" if due < AS_OF - timedelta(days=30) else "DUE"
                    else:
                        status = "OVERDUE" if due < AS_OF - timedelta(days=30) else "DUE"
                self.tables["dbo.premium_schedule"].append((sid, pol.policy_id, n, due, amount, paid, status))
            # unallocated top-ups and refunds
            if self.rng.random() < 0.08 and pol.inception <= AS_OF:
                self._payment(pol, None, min(AS_OF, pol.inception + timedelta(days=45)),
                              Decimal(self.rng.randint(500, 5000)) / 100)

    def _payment(self, pol: Policy, sid: int | None, due: date, amount: Decimal) -> None:
        paid_day = min(AS_OF, due + timedelta(days=self.rng.randint(-5, 10)))
        paid_at = self.ts(paid_day)
        method = self.rng.choices(["SEPA_DD", "CARD", "TRANSFER"], [70, 15, 15])[0]
        iban = self.iban(self.holder_country[pol.policyholder_id]) if method != "CARD" else None
        r = self.rng.random()
        ref = None if r < 0.1 else ("" if r < 0.15 else f"{pol.policy_number}/{sid or 'X'}")
        row = [self.uid(), pol.policy_id, sid, self.dto(paid_at), amount, method, iban, ref]
        self.tables["dbo.premium_payment"].append(tuple(row))
        if pol.policy_id <= 4 and sid is not None:
            # ties on the latest timestamp: a duplicate card retry at the same instant
            dup = list(row)
            dup[0], dup[2], dup[5], dup[6] = self.uid(), None, "CARD", None
            dup[4] = Decimal("0.0050") if pol.policy_id == 4 else Decimal("1.00")
            self.tables["dbo.premium_payment"].append(tuple(dup))

    # -- claims -----------------------------------------------------------------
    def claims(self) -> None:
        eligible = [p for p in self.policies if p.status != "QUOTE" and p.inception <= AS_OF - timedelta(days=5)]
        edge_losses = [date(2026, 1, 31), date(2025, 12, 31), date(2026, 7, 31), date(2026, 8, 31), date(2026, 5, 31)]
        cid = 0
        while cid < N_CLAIMS:
            pol = self.rng.choice(eligible)
            expiry = add_year_minus_day(pol.inception)
            last = min(expiry, AS_OF)
            loss = pol.inception + timedelta(days=self.rng.randint(0, (last - pol.inception).days))
            if cid < len(edge_losses):
                edge = edge_losses[cid]
                candidates = [p for p in eligible if p.inception <= edge <= add_year_minus_day(p.inception)]
                pol, loss = candidates[cid], edge
            cid += 1
            reported = self.ts(min(AS_OF, loss + timedelta(days=self.rng.choice([0, 1, 2, 3, 5, 8, 13, 21, 40]))))
            cause = self.rng.choice(CAUSES)
            r = self.rng.random()
            if r < 0.06:
                cause = None
            elif r < 0.10:
                cause = cause.lower()
            elif r < 0.13:
                cause = cause.title()
            age = (AS_OF - loss).days
            r = self.rng.random()
            if r < 0.10:
                status = "DENIED"
            elif age < 60 or r < 0.35:
                status = "OPEN"
            elif r < 0.40:
                status = "REOPENED"
            else:
                status = "CLOSED"
            desc = None if self.rng.random() < 0.1 else self.rng.choice(
                ["Water ingress from upstairs flat", "Rear-end collision at junction", "Hail damage to roof",
                 "Bicycle stolen from garage", "Windscreen chip", "Kitchen fire", "Dog bit a neighbour", ""])
            closed_at = None
            if status in ("CLOSED", "DENIED"):
                closed_at = min(datetime(AS_OF.year, AS_OF.month, AS_OF.day, 18, 0, 0),
                                reported.replace(microsecond=0) + timedelta(days=self.rng.randint(10, 200)))
            number = f"C{500000 + cid:09d}"
            self.tables["dbo.claim"].append((cid, number, pol.policy_id, loss, reported.replace(microsecond=0),
                                             cause, status, desc, closed_at))
            if status == "DENIED":
                continue
            band = self.rng.choices([(10000, 200000), (200000, 600000), (600000, 3000000)], [75, 22, 3])[0]
            estimate = min(pol.sum_insured, Decimal(self.rng.randint(*band)) / 100)
            for rtype in ["INDEMNITY"] + (["EXPENSE"] if self.rng.random() < 0.4 else []):
                reserve = estimate if rtype == "INDEMNITY" else (estimate * Decimal("0.08")).quantize(CENT)
                n_pay = 0 if status == "OPEN" and self.rng.random() < 0.5 else self.rng.randint(1, 3)
                paid_total = Decimal("0")
                for k in range(n_pay):
                    share = Decimal(self.rng.randint(15, 45)) / 100
                    amount = (reserve * share).quantize(CENT)
                    if self.rng.random() < 0.05:
                        amount += Decimal("0.005")
                    if paid_total + amount > reserve:
                        break
                    paid_total += amount
                    pay_at = reported + timedelta(days=5 + 15 * k, hours=self.rng.randint(0, 8))
                    pay_at = min(pay_at, datetime(AS_OF.year, AS_OF.month, AS_OF.day, 17, 0, 0))
                    payee = self.fakers[self.holder_country[pol.policyholder_id]].name()
                    self.tables["dbo.claim_payment"].append((cid, rtype, pay_at, amount, payee,
                                                             None if self.rng.random() < 0.2 else self.iban("DE")))
                if status == "CLOSED":
                    reserve = paid_total
                set_at = (closed_at if status == "CLOSED" else reported).replace(microsecond=0)
                self.tables["dbo.claim_reserve"].append((cid, rtype, reserve, set_at,
                                                         "claims.close" if status == "CLOSED" else "claims.intake"))

    def audit_history(self) -> None:
        for pol in self.policies:
            if pol.status in ("LAPSED", "CANCELLED"):
                when = datetime.combine(min(AS_OF, pol.inception + timedelta(days=120)), datetime.min.time()) + timedelta(hours=2)
                self.tables["dbo.audit_log"].append(("policy", "STATUS", pol.policy_number, "ACTIVE", pol.status, 1,
                                                     when, "legacy.batch"))

    def generate(self) -> dict[str, list[tuple]]:
        self.reference()
        self.brokers()
        self.policyholders()
        self.policies_and_versions()
        self.schedules_and_payments()
        self.claims()
        self.audit_history()
        return self.tables


# column lists (identity columns are loaded explicitly so both engines share keys)
COLUMNS = {
    "ref.country": ["country_code", "country_name", "currency_code", "is_eu_member", "premium_tax_rate"],
    "ref.product": ["product_id", "product_code", "product_name", "line_of_business", "base_rate", "min_premium", "is_active"],
    "dbo.broker": ["broker_id", "broker_code", "broker_name", "country_code", "commission_pct", "email", "is_active", "created_at"],
    "dbo.policyholder": ["policyholder_id", "external_ref", "first_name", "middle_name", "last_name", "date_of_birth", "email",
                         "phone", "iban", "address_line", "postcode", "city", "country_code", "created_at"],
    "dbo.policy": ["policy_id", "policy_number", "policyholder_id", "broker_id", "product_id", "status", "inception_date",
                   "expiry_date", "payment_frequency", "annual_premium", "currency_code", "created_at", "updated_at"],
    "dbo.policy_version": ["policy_id", "version_no", "effective_from", "effective_to", "sum_insured", "annual_premium",
                           "change_reason", "created_at"],
    "dbo.coverage": ["policy_id", "coverage_code", "limit_amount", "deductible", "premium_share"],
    "dbo.premium_schedule": ["schedule_id", "policy_id", "installment_no", "due_date", "amount_due", "paid_amount", "status"],
    "dbo.premium_payment": ["payment_ref", "policy_id", "schedule_id", "paid_at", "amount", "method", "payer_iban", "reference_text"],
    "dbo.claim": ["claim_id", "claim_number", "policy_id", "loss_date", "reported_at", "cause_code", "status", "description", "closed_at"],
    "dbo.claim_reserve": ["claim_id", "reserve_type", "amount", "set_at", "set_by"],
    "dbo.claim_payment": ["claim_id", "reserve_type", "paid_at", "amount", "payee_name", "payee_iban"],
    "dbo.audit_log": ["table_name", "action", "key_value", "old_value", "new_value", "row_count", "changed_at", "changed_by"],
}
IDENTITY_TABLES = {"ref.product", "dbo.broker", "dbo.policyholder", "dbo.policy", "dbo.premium_schedule", "dbo.claim"}
TRIGGER_TABLES = ["dbo.policy", "dbo.claim", "dbo.claim_payment"]


def load(tables: dict[str, list[tuple]]) -> None:
    conn = mssql_connect(autocommit=False)
    cur = conn.cursor()
    cur.fast_executemany = True
    for t in TRIGGER_TABLES:
        cur.execute(f"DISABLE TRIGGER ALL ON {t}")
    for table, cols in COLUMNS.items():
        rows = tables[table]
        if not rows:
            continue
        if table in IDENTITY_TABLES:
            cur.execute(f"SET IDENTITY_INSERT {table} ON")
        sql = f"INSERT INTO {table} ({', '.join(cols)}) VALUES ({', '.join('?' * len(cols))})"
        for i in range(0, len(rows), 2000):
            cur.executemany(sql, rows[i:i + 2000])
        if table in IDENTITY_TABLES:
            cur.execute(f"SET IDENTITY_INSERT {table} OFF")
        print(f"  {table:24s} {len(rows):>6d} rows")
    for t in TRIGGER_TABLES:
        cur.execute(f"ENABLE TRIGGER ALL ON {t}")
    # keep business-number sequences ahead of the seeded rows
    cur.execute(f"ALTER SEQUENCE dbo.seq_policy_number RESTART WITH {100001 + N_POLICIES}")
    cur.execute(f"ALTER SEQUENCE dbo.seq_claim_number RESTART WITH {500001 + N_CLAIMS}")
    conn.commit()
    conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="generate and print row counts only")
    args = parser.parse_args()
    tables = Generator().generate()
    if args.dry_run:
        for t, rows in tables.items():
            print(f"{t:24s} {len(rows):>6d}")
        return
    load(tables)


if __name__ == "__main__":
    main()

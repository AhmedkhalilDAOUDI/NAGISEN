import { getState } from "./store.js";

// Every country the browser can name, in the person's own language.
const names = new Intl.DisplayNames([navigator.language, "en"], { type: "region" });
const CODES = ("AD AE AF AG AI AL AM AO AR AS AT AU AW AZ BA BB BD BE BF BG BH BI BJ BM BN BO BR BS BT BW BY BZ CA CD CF CG " +
  "CH CI CL CM CN CO CR CU CV CY CZ DE DJ DK DM DO DZ EC EE EG ER ES ET FI FJ FM FR GA GB GD GE GH GM GN GQ GR GT GW GY HK " +
  "HN HR HT HU ID IE IL IN IQ IR IS IT JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD " +
  "ME MG MH MK ML MM MN MO MR MT MU MV MW MX MY MZ NA NE NG NI NL NO NP NR NZ OM PA PE PG PH PK PL PR PS PT PW PY QA RO RS " +
  "RU RW SA SB SC SD SE SG SI SK SL SM SN SO SR SS ST SV SY SZ TD TG TH TJ TL TM TN TO TR TT TV TW TZ UA UG US UY UZ VA VC " +
  "VE VN VU WS YE ZA ZM ZW").split(" ");
export const COUNTRIES = CODES.map((code) => ({ code, name: names.of(code) || code }))
  .sort((a, b) => a.name.localeCompare(b.name));

// The browser has no country-to-currency table, so the common ones are listed; euro countries share one.
const EURO = "AD AT BE CY DE EE ES FI FR GR HR IE IT LT LU LV MC ME MT NL PT SI SK SM VA".split(" ");
const CURRENCY = { MA: "MAD", US: "USD", GB: "GBP", CA: "CAD", AU: "AUD", NZ: "NZD", CH: "CHF", JP: "JPY", CN: "CNY",
  IN: "INR", BR: "BRL", MX: "MXN", AE: "AED", SA: "SAR", QA: "QAR", KW: "KWD", BH: "BHD", OM: "OMR", EG: "EGP", DZ: "DZD",
  TN: "TND", TR: "TRY", SE: "SEK", NO: "NOK", DK: "DKK", PL: "PLN", CZ: "CZK", HU: "HUF", RO: "RON", BG: "BGN", RU: "RUB",
  UA: "UAH", ZA: "ZAR", NG: "NGN", KE: "KES", GH: "GHS", SN: "XOF", CI: "XOF", CM: "XAF", KR: "KRW", SG: "SGD", HK: "HKD",
  TW: "TWD", TH: "THB", ID: "IDR", MY: "MYR", PH: "PHP", VN: "VND", PK: "PKR", BD: "BDT", IL: "ILS", JO: "JOD", LB: "LBP",
  AR: "ARS", CL: "CLP", CO: "COP", PE: "PEN", IS: "ISK", RS: "RSD", GE: "GEL", AM: "AMD", AZ: "AZN", KZ: "KZT", IQ: "IQD" };
export const currencyFor = (code) => (EURO.includes(code) ? "EUR" : CURRENCY[code] || "USD");

export const currency = () => currencyFor(getState().profile.country || "MA");

export const money = (value) => {
  const digits = value >= 100 ? 0 : value >= 10 ? 1 : 2;
  return `${Number(value).toLocaleString(undefined, { maximumFractionDigits: digits })} ${currency()}`;
};

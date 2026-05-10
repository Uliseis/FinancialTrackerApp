import { createSign } from "node:crypto";
import { env } from "@/lib/env";

const BASE_URL = "https://api.enablebanking.com";

export interface Aspsp {
  name: string;
  country: string;
  logo?: string;
  psu_types?: string[];
  auth_methods?: { name: string; psu_type?: string; approach?: string }[];
  maximum_consent_validity?: number;
  beta?: boolean;
  bic?: string;
}

export interface AspspsResponse {
  aspsps: Aspsp[];
}

export interface AuthRequest {
  access: {
    valid_until: string;
    accounts?: { iban?: string; other?: { identification: string; scheme_name: string } }[];
    balances?: boolean;
    transactions?: boolean;
  };
  aspsp: { name: string; country: string };
  state: string;
  redirect_url: string;
  psu_type: "personal" | "business";
  language?: string;
  auth_method?: string;
}

export interface AuthResponse {
  url: string;
  authorization_id: string;
}

export interface SessionAccount {
  uid: string;
  identification_hash?: string;
  identification_hashes?: string[];
  account_id?: { iban?: string; other?: { identification: string; scheme_name: string } };
  account_servicer?: { bic_fi?: string; financial_institution_id?: string };
  details?: string;
  usage?: string;
  cash_account_type?: string;
  product?: string;
  currency?: string;
  name?: string;
  product_name?: string;
}

export interface SessionResponse {
  session_id: string;
  status: "AUTHORIZED" | "PENDING_AUTHORIZATION" | "INVALID" | "REVOKED" | "CLOSED" | string;
  accounts: SessionAccount[];
  access: {
    valid_until: string;
    balances?: boolean;
    transactions?: boolean;
  };
  aspsp: { name: string; country: string };
  psu_type: string;
  created: string;
  authorized?: string;
  closed?: string;
}

export interface AccountDetails {
  account_id?: { iban?: string; other?: { identification: string; scheme_name: string } };
  account_servicer?: { bic_fi?: string; financial_institution_id?: string };
  name?: string;
  details?: string;
  usage?: string;
  cash_account_type?: string;
  product?: string;
  currency: string;
  psu_status?: string;
  credit_limit?: { currency: string; amount: string };
  legal_age?: boolean;
  postal_address?: Record<string, unknown>;
  uid?: string;
}

export interface AmountType {
  currency: string;
  amount: string;
}

export type BalanceStatus =
  | "CLAV"
  | "CLBD"
  | "FWAV"
  | "INFO"
  | "ITAV"
  | "ITBD"
  | "OPAV"
  | "OPBD"
  | "PRCD"
  | "XPCD";

export interface Balance {
  name: string;
  balance_amount: AmountType;
  balance_type: BalanceStatus;
  last_change_date_time?: string;
  reference_date?: string;
  last_committed_transaction?: string;
}

export interface BalancesResponse {
  balances: Balance[];
}

export interface PartyIdentification {
  name?: string;
  postal_address?: Record<string, unknown>;
}

export interface AccountIdentification {
  iban?: string;
  other?: { identification: string; scheme_name: string; issuer?: string };
}

export interface EbTransaction {
  entry_reference?: string;
  merchant_category_code?: string;
  transaction_amount: AmountType;
  creditor?: PartyIdentification;
  creditor_account?: AccountIdentification;
  creditor_agent?: { bic_fi?: string };
  debtor?: PartyIdentification;
  debtor_account?: AccountIdentification;
  debtor_agent?: { bic_fi?: string };
  bank_transaction_code?: { description?: string; code?: string; sub_code?: string };
  credit_debit_indicator: "CRDT" | "DBIT";
  status: string;
  booking_date?: string;
  value_date?: string;
  transaction_date?: string;
  balance_after_transaction?: AmountType;
  reference_number?: string;
  remittance_information?: string[];
  exchange_rate?: { unit_currency: string; exchange_rate: string; rate_type?: string };
  note?: string;
  transaction_id?: string;
}

export interface TransactionsResponse {
  transactions: EbTransaction[];
  continuation_key?: string;
}

export interface PsuHeaders {
  ipAddress?: string;
  userAgent?: string;
}

export class EnableBankingError extends Error {
  status: number;
  body: unknown;
  constructor(message: string, status: number, body: unknown) {
    super(`EnableBanking ${status}: ${message}`);
    this.status = status;
    this.body = body;
  }
}

function base64url(input: Buffer | string): string {
  const buf = typeof input === "string" ? Buffer.from(input) : input;
  return buf.toString("base64").replace(/=+$/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function signJwt(): string {
  const now = Math.floor(Date.now() / 1000);
  const header = { typ: "JWT", alg: "RS256", kid: env.ENABLEBANKING_APPLICATION_ID };
  const payload = {
    iss: "enablebanking.com",
    aud: "api.enablebanking.com",
    iat: now,
    exp: now + 3600,
  };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signer = createSign("RSA-SHA256");
  signer.update(signingInput);
  const signature = signer.sign(env.ENABLEBANKING_PRIVATE_KEY);
  return `${signingInput}.${base64url(signature)}`;
}

export class EnableBankingClient {
  private psu?: PsuHeaders;

  constructor(psu?: PsuHeaders) {
    this.psu = psu;
  }

  private async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${signJwt()}`,
      Accept: "application/json",
    };
    if (init.body) headers["Content-Type"] = "application/json";
    if (this.psu?.ipAddress) headers["psu-ip-address"] = this.psu.ipAddress;
    if (this.psu?.userAgent) headers["psu-user-agent"] = this.psu.userAgent;

    const res = await fetch(`${BASE_URL}${path}`, {
      ...init,
      headers: { ...headers, ...(init.headers as Record<string, string> | undefined) },
      cache: "no-store",
    });
    if (!res.ok) {
      const text = await res.text();
      let body: unknown = text;
      try {
        body = JSON.parse(text);
      } catch {
        // keep raw text
      }
      throw new EnableBankingError(`${path} failed`, res.status, body);
    }
    if (res.status === 204) return undefined as T;
    return (await res.json()) as T;
  }

  async listAspsps(opts: { country?: string; psuType?: "personal" | "business" } = {}): Promise<Aspsp[]> {
    const params = new URLSearchParams();
    if (opts.country) params.set("country", opts.country);
    if (opts.psuType) params.set("psu_type", opts.psuType);
    const qs = params.toString();
    const data = await this.request<AspspsResponse>(`/aspsps${qs ? `?${qs}` : ""}`);
    return data.aspsps;
  }

  startAuth(input: AuthRequest): Promise<AuthResponse> {
    return this.request<AuthResponse>("/auth", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  createSession(code: string): Promise<SessionResponse> {
    return this.request<SessionResponse>("/sessions", {
      method: "POST",
      body: JSON.stringify({ code }),
    });
  }

  getSession(sessionId: string): Promise<SessionResponse> {
    return this.request<SessionResponse>(`/sessions/${sessionId}`);
  }

  closeSession(sessionId: string): Promise<void> {
    return this.request<void>(`/sessions/${sessionId}`, { method: "DELETE" });
  }

  getAccountDetails(accountUid: string): Promise<AccountDetails> {
    return this.request<AccountDetails>(`/accounts/${accountUid}/details`);
  }

  getAccountBalances(accountUid: string): Promise<BalancesResponse> {
    return this.request<BalancesResponse>(`/accounts/${accountUid}/balances`);
  }

  getAccountTransactions(
    accountUid: string,
    opts: {
      dateFrom?: string;
      dateTo?: string;
      transactionStatus?: "BOOK" | "PDNG" | "OTHR";
      continuationKey?: string;
      strategy?: "default" | "longest";
    } = {},
  ): Promise<TransactionsResponse> {
    const params = new URLSearchParams();
    if (opts.dateFrom) params.set("date_from", opts.dateFrom);
    if (opts.dateTo) params.set("date_to", opts.dateTo);
    if (opts.transactionStatus) params.set("transaction_status", opts.transactionStatus);
    if (opts.continuationKey) params.set("continuation_key", opts.continuationKey);
    if (opts.strategy) params.set("strategy", opts.strategy);
    const qs = params.toString();
    return this.request<TransactionsResponse>(
      `/accounts/${accountUid}/transactions${qs ? `?${qs}` : ""}`,
    );
  }
}

export function preferredBalance(balances: Balance[]): Balance | undefined {
  const order: BalanceStatus[] = ["CLBD", "ITBD", "ITAV", "CLAV", "OPAV", "OPBD", "FWAV", "PRCD", "XPCD", "INFO"];
  for (const t of order) {
    const found = balances.find((b) => b.balance_type === t);
    if (found) return found;
  }
  return balances[0];
}

export function pickBookingDate(t: EbTransaction): Date {
  const candidate = t.booking_date ?? t.value_date ?? t.transaction_date;
  if (!candidate) throw new Error("Transaction has no booking/value/transaction date");
  const d = new Date(candidate);
  if (Number.isNaN(d.getTime())) throw new Error(`Invalid date: ${candidate}`);
  return d;
}

export function pickValueDate(t: EbTransaction): Date | null {
  const candidate = t.value_date ?? t.transaction_date;
  if (!candidate) return null;
  const d = new Date(candidate);
  return Number.isNaN(d.getTime()) ? null : d;
}

export function pickExternalId(t: EbTransaction, fallback: string): string {
  return t.transaction_id ?? t.entry_reference ?? fallback;
}

export function pickDescription(t: EbTransaction): string {
  if (t.remittance_information?.length) return t.remittance_information.join(" ");
  if (t.note) return t.note;
  if (t.bank_transaction_code?.description) return t.bank_transaction_code.description;
  return "";
}

export function pickCounterparty(t: EbTransaction): string | null {
  if (t.credit_debit_indicator === "CRDT") return t.debtor?.name ?? null;
  return t.creditor?.name ?? null;
}

export function signedAmount(t: EbTransaction): string {
  const raw = t.transaction_amount.amount;
  const cleaned = raw.replace(/^[+-]/, "");
  return t.credit_debit_indicator === "DBIT" ? `-${cleaned}` : cleaned;
}

export function ibanOf(account: SessionAccount | AccountDetails): string | null {
  return account.account_id?.iban ?? null;
}

import { env } from "@/lib/env";

const BASE_URL = "https://bankaccountdata.gocardless.com/api/v2";

export interface Institution {
  id: string;
  name: string;
  bic: string;
  transaction_total_days: string;
  countries: string[];
  logo: string;
}

export interface EndUserAgreement {
  id: string;
  created: string;
  max_historical_days: number;
  access_valid_for_days: number;
  access_scope: string[];
  institution_id: string;
}

export interface Requisition {
  id: string;
  created: string;
  redirect: string;
  status: string;
  institution_id: string;
  agreement: string;
  reference: string;
  accounts: string[];
  user_language: string;
  link: string;
}

export interface AccountDetails {
  account: {
    resourceId?: string;
    iban?: string;
    bban?: string;
    currency: string;
    name?: string;
    ownerName?: string;
    product?: string;
    cashAccountType?: string;
    bic?: string;
  };
}

export interface Balance {
  balanceAmount: { amount: string; currency: string };
  balanceType: string;
  referenceDate?: string;
}

export interface BalancesResponse {
  balances: Balance[];
}

export interface GcTransaction {
  transactionId?: string;
  internalTransactionId?: string;
  bookingDate?: string;
  valueDate?: string;
  bookingDateTime?: string;
  valueDateTime?: string;
  transactionAmount: { amount: string; currency: string };
  creditorName?: string;
  debtorName?: string;
  remittanceInformationUnstructured?: string;
  remittanceInformationUnstructuredArray?: string[];
  proprietaryBankTransactionCode?: string;
  bankTransactionCode?: string;
  additionalInformation?: string;
}

export interface TransactionsResponse {
  transactions: {
    booked: GcTransaction[];
    pending?: GcTransaction[];
  };
}

export class GoCardlessError extends Error {
  status: number;
  body: unknown;
  constructor(message: string, status: number, body: unknown) {
    super(`GoCardless ${status}: ${message}`);
    this.status = status;
    this.body = body;
  }
}

export class GoCardlessClient {
  private accessToken: string | null = null;
  private accessTokenExpiresAt = 0;

  private async getAccessToken(): Promise<string> {
    if (this.accessToken && Date.now() < this.accessTokenExpiresAt - 60_000) {
      return this.accessToken;
    }
    const res = await fetch(`${BASE_URL}/token/new/`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        secret_id: env.GOCARDLESS_SECRET_ID,
        secret_key: env.GOCARDLESS_SECRET_KEY,
      }),
      cache: "no-store",
    });
    if (!res.ok) {
      const text = await res.text();
      throw new GoCardlessError("token request failed", res.status, text);
    }
    const data = (await res.json()) as { access: string; access_expires: number };
    this.accessToken = data.access;
    this.accessTokenExpiresAt = Date.now() + data.access_expires * 1000;
    return data.access;
  }

  private async request<T>(
    path: string,
    init: RequestInit = {},
  ): Promise<T> {
    const token = await this.getAccessToken();
    const res = await fetch(`${BASE_URL}${path}`, {
      ...init,
      headers: {
        ...(init.headers ?? {}),
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
        ...(init.body ? { "Content-Type": "application/json" } : {}),
      },
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
      throw new GoCardlessError(`${path} failed`, res.status, body);
    }
    return (await res.json()) as T;
  }

  listInstitutions(country: string): Promise<Institution[]> {
    return this.request<Institution[]>(
      `/institutions/?country=${encodeURIComponent(country)}`,
    );
  }

  createAgreement(input: {
    institutionId: string;
    maxHistoricalDays?: number;
    accessValidForDays?: number;
    accessScope?: string[];
  }): Promise<EndUserAgreement> {
    return this.request<EndUserAgreement>("/agreements/enduser/", {
      method: "POST",
      body: JSON.stringify({
        institution_id: input.institutionId,
        max_historical_days: input.maxHistoricalDays ?? 90,
        access_valid_for_days: input.accessValidForDays ?? 90,
        access_scope: input.accessScope ?? ["balances", "details", "transactions"],
      }),
    });
  }

  createRequisition(input: {
    redirect: string;
    institutionId: string;
    agreementId?: string;
    reference: string;
    userLanguage?: string;
  }): Promise<Requisition> {
    return this.request<Requisition>("/requisitions/", {
      method: "POST",
      body: JSON.stringify({
        redirect: input.redirect,
        institution_id: input.institutionId,
        agreement: input.agreementId,
        reference: input.reference,
        user_language: input.userLanguage ?? "EN",
      }),
    });
  }

  getRequisition(id: string): Promise<Requisition> {
    return this.request<Requisition>(`/requisitions/${id}/`);
  }

  deleteRequisition(id: string): Promise<{ summary: string; detail: string }> {
    return this.request(`/requisitions/${id}/`, { method: "DELETE" });
  }

  getAccountDetails(accountId: string): Promise<AccountDetails> {
    return this.request<AccountDetails>(`/accounts/${accountId}/details/`);
  }

  getAccountBalances(accountId: string): Promise<BalancesResponse> {
    return this.request<BalancesResponse>(`/accounts/${accountId}/balances/`);
  }

  getAccountTransactions(
    accountId: string,
    opts: { dateFrom?: string; dateTo?: string } = {},
  ): Promise<TransactionsResponse> {
    const params = new URLSearchParams();
    if (opts.dateFrom) params.set("date_from", opts.dateFrom);
    if (opts.dateTo) params.set("date_to", opts.dateTo);
    const qs = params.toString();
    return this.request<TransactionsResponse>(
      `/accounts/${accountId}/transactions/${qs ? `?${qs}` : ""}`,
    );
  }
}

export function pickBookingDate(t: GcTransaction): Date {
  const candidate = t.bookingDateTime ?? t.bookingDate ?? t.valueDateTime ?? t.valueDate;
  if (!candidate) throw new Error("Transaction has no booking/value date");
  const d = new Date(candidate);
  if (Number.isNaN(d.getTime())) throw new Error(`Invalid date: ${candidate}`);
  return d;
}

export function pickExternalId(t: GcTransaction, fallback: string): string {
  return t.transactionId ?? t.internalTransactionId ?? fallback;
}

export function pickDescription(t: GcTransaction): string {
  if (t.remittanceInformationUnstructured) return t.remittanceInformationUnstructured;
  if (t.remittanceInformationUnstructuredArray?.length) {
    return t.remittanceInformationUnstructuredArray.join(" ");
  }
  return t.additionalInformation ?? "";
}

export function pickCounterparty(t: GcTransaction): string | null {
  return t.creditorName ?? t.debtorName ?? null;
}

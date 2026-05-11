import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

function isValidIsoCurrency(code: string | null | undefined): code is string {
  return !!code && /^[A-Z]{3}$/.test(code) && code !== "XXX";
}

export function formatCurrency(amount: number, currency: string | null | undefined = "EUR") {
  const ccy = isValidIsoCurrency(currency) ? currency : null;
  if (!ccy) {
    return new Intl.NumberFormat("en-IE", {
      maximumFractionDigits: 2,
      minimumFractionDigits: 2,
    }).format(amount);
  }
  try {
    return new Intl.NumberFormat("en-IE", {
      style: "currency",
      currency: ccy,
      maximumFractionDigits: 2,
    }).format(amount);
  } catch {
    return new Intl.NumberFormat("en-IE", {
      maximumFractionDigits: 2,
      minimumFractionDigits: 2,
    }).format(amount);
  }
}

export function formatDate(d: Date | string) {
  const date = typeof d === "string" ? new Date(d) : d;
  return new Intl.DateTimeFormat("en-GB", {
    year: "numeric",
    month: "short",
    day: "2-digit",
  }).format(date);
}

export function monthStart(d: Date, offset = 0): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + offset, 1));
}

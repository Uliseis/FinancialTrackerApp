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

const RTF = new Intl.RelativeTimeFormat("en", { numeric: "auto" });

export function formatRelativeTime(d: Date | string): string {
  const date = typeof d === "string" ? new Date(d) : d;
  const diffSec = (date.getTime() - Date.now()) / 1000;
  const abs = Math.abs(diffSec);
  if (abs < 60) return RTF.format(Math.round(diffSec), "second");
  if (abs < 3600) return RTF.format(Math.round(diffSec / 60), "minute");
  if (abs < 86400) return RTF.format(Math.round(diffSec / 3600), "hour");
  if (abs < 2592000) return RTF.format(Math.round(diffSec / 86400), "day");
  if (abs < 31536000) return RTF.format(Math.round(diffSec / 2592000), "month");
  return RTF.format(Math.round(diffSec / 31536000), "year");
}

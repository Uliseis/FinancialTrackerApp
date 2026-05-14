"use client";

import {
  Area,
  AreaChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { formatCurrency } from "@/lib/utils";

export interface PortfolioSeriesPoint {
  date: string;
  marketValueEur: number;
  costBasisEur: number;
}

export function PortfolioChart({ data }: { data: PortfolioSeriesPoint[] }) {
  if (data.length === 0) {
    return (
      <div className="flex h-64 items-center justify-center text-sm text-muted-foreground">
        No valuations yet — set a baseline for each account to start the chart.
      </div>
    );
  }

  return (
    <div className="h-72 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
          <defs>
            <linearGradient id="mv" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--color-chart-1)" stopOpacity={0.4} />
              <stop offset="100%" stopColor="var(--color-chart-1)" stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke="var(--color-border)" strokeDasharray="3 3" />
          <XAxis
            dataKey="date"
            stroke="var(--color-muted-foreground)"
            fontSize={11}
            tickMargin={6}
          />
          <YAxis
            stroke="var(--color-muted-foreground)"
            fontSize={11}
            tickFormatter={(v: number) => formatCurrency(v, "EUR")}
            width={86}
          />
          <Tooltip
            contentStyle={{
              background: "var(--color-card)",
              border: "1px solid var(--color-border)",
              borderRadius: 8,
              fontSize: 12,
            }}
            formatter={(value, key) => [
              formatCurrency(Number(value), "EUR"),
              key === "marketValueEur" ? "Market value" : "Cost basis",
            ]}
            labelStyle={{ color: "var(--color-foreground)" }}
          />
          <Legend
            iconType="circle"
            wrapperStyle={{ fontSize: 12 }}
            formatter={(value: string) =>
              value === "marketValueEur" ? "Market value" : "Cost basis"
            }
          />
          <Area
            type="monotone"
            dataKey="marketValueEur"
            stroke="var(--color-chart-1)"
            strokeWidth={2}
            fill="url(#mv)"
          />
          <Area
            type="monotone"
            dataKey="costBasisEur"
            stroke="var(--color-chart-2)"
            strokeWidth={2}
            fill="transparent"
            strokeDasharray="4 4"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}

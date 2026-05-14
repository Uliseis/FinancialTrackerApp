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
  cashEur: number;
  positionsEur: number;
}

const LABELS: Record<string, string> = {
  marketValueEur: "Market value",
  costBasisEur: "Cost basis",
  cashEur: "Cash",
  positionsEur: "Positions",
};

export function PortfolioChart({ data }: { data: PortfolioSeriesPoint[] }) {
  if (data.length === 0) {
    return (
      <div className="flex h-64 items-center justify-center text-sm text-muted-foreground">
        No valuations yet — set a baseline for each account to start the chart.
      </div>
    );
  }

  const hasCashSplit = data.some((d) => d.cashEur > 0);

  return (
    <div className="h-72 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
          <defs>
            <linearGradient id="positions" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--color-chart-1)" stopOpacity={0.5} />
              <stop offset="100%" stopColor="var(--color-chart-1)" stopOpacity={0.05} />
            </linearGradient>
            <linearGradient id="cash" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--color-chart-3)" stopOpacity={0.5} />
              <stop offset="100%" stopColor="var(--color-chart-3)" stopOpacity={0.05} />
            </linearGradient>
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
              LABELS[String(key)] ?? String(key),
            ]}
            labelStyle={{ color: "var(--color-foreground)" }}
          />
          <Legend
            iconType="circle"
            wrapperStyle={{ fontSize: 12 }}
            formatter={(value: string) => LABELS[value] ?? value}
          />
          {hasCashSplit ? (
            <>
              <Area
                type="monotone"
                stackId="value"
                dataKey="positionsEur"
                stroke="var(--color-chart-1)"
                strokeWidth={2}
                fill="url(#positions)"
              />
              <Area
                type="monotone"
                stackId="value"
                dataKey="cashEur"
                stroke="var(--color-chart-3)"
                strokeWidth={2}
                fill="url(#cash)"
              />
            </>
          ) : (
            <Area
              type="monotone"
              dataKey="marketValueEur"
              stroke="var(--color-chart-1)"
              strokeWidth={2}
              fill="url(#mv)"
            />
          )}
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

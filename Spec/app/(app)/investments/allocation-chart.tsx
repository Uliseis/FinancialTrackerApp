"use client";

import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from "recharts";
import { formatCurrency } from "@/lib/utils";

const PALETTE = [
  "var(--color-chart-1)",
  "var(--color-chart-2)",
  "var(--color-chart-3)",
  "var(--color-chart-4)",
  "var(--color-chart-5)",
];

export interface AllocationDatum {
  name: string;
  value: number;
}

export function AllocationChart({ data }: { data: AllocationDatum[] }) {
  const total = data.reduce((acc, d) => acc + d.value, 0);
  if (data.length === 0 || total <= 0) {
    return (
      <div className="flex h-48 items-center justify-center text-sm text-muted-foreground">
        No valuations yet.
      </div>
    );
  }

  return (
    <div className="h-48 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <PieChart>
          <Pie
            data={data}
            dataKey="value"
            nameKey="name"
            innerRadius={42}
            outerRadius={70}
            paddingAngle={2}
            stroke="var(--color-card)"
          >
            {data.map((_, i) => (
              <Cell key={i} fill={PALETTE[i % PALETTE.length]} />
            ))}
          </Pie>
          <Tooltip
            contentStyle={{
              background: "var(--color-card)",
              border: "1px solid var(--color-border)",
              borderRadius: 8,
              fontSize: 12,
            }}
            formatter={(value) => formatCurrency(Number(value), "EUR")}
            labelStyle={{ color: "var(--color-foreground)" }}
          />
        </PieChart>
      </ResponsiveContainer>
    </div>
  );
}

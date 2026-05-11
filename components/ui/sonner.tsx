"use client";

import { Toaster as Sonner, type ToasterProps } from "sonner";

export function Toaster(props: ToasterProps) {
  return (
    <Sonner
      theme="dark"
      className="toaster group"
      toastOptions={{
        classNames: {
          toast:
            "group toast group-[.toaster]:bg-[var(--color-popover)] group-[.toaster]:text-[var(--color-popover-foreground)] group-[.toaster]:border group-[.toaster]:border-[var(--color-border)] group-[.toaster]:shadow-lg",
          description: "group-[.toast]:text-[var(--color-muted-foreground)]",
          actionButton:
            "group-[.toast]:bg-[var(--color-primary)] group-[.toast]:text-[var(--color-primary-foreground)]",
          cancelButton:
            "group-[.toast]:bg-[var(--color-muted)] group-[.toast]:text-[var(--color-muted-foreground)]",
        },
      }}
      {...props}
    />
  );
}

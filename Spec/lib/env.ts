function required(name: string): string {
  const value = process.env[name];
  if (!value || value.length === 0) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

function optional(name: string): string | undefined {
  const value = process.env[name];
  return value && value.length > 0 ? value : undefined;
}

function decodePrivateKey(raw: string): string {
  if (raw.includes("BEGIN")) return raw;
  return Buffer.from(raw, "base64").toString("utf8");
}

export const env = {
  get DATABASE_URL() {
    return required("DATABASE_URL");
  },
  get NEXTAUTH_SECRET() {
    return required("NEXTAUTH_SECRET");
  },
  get NEXTAUTH_URL() {
    return optional("NEXTAUTH_URL") ?? "http://localhost:3000";
  },
  get GITHUB_ID() {
    return required("GITHUB_ID");
  },
  get GITHUB_SECRET() {
    return required("GITHUB_SECRET");
  },
  get ALLOWED_EMAIL() {
    return required("ALLOWED_EMAIL");
  },
  get ENCRYPTION_KEY() {
    return required("ENCRYPTION_KEY");
  },
  get ENABLEBANKING_APPLICATION_ID() {
    return required("ENABLEBANKING_APPLICATION_ID");
  },
  get ENABLEBANKING_PRIVATE_KEY() {
    return decodePrivateKey(required("ENABLEBANKING_PRIVATE_KEY"));
  },
  get ENABLEBANKING_REDIRECT_URL() {
    return (
      optional("ENABLEBANKING_REDIRECT_URL") ??
      `${optional("NEXTAUTH_URL") ?? "http://localhost:3000"}/api/enablebanking/callback`
    );
  },
};

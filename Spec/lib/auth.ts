import NextAuth from "next-auth";
import GitHub from "next-auth/providers/github";

const allowedEmail = process.env.ALLOWED_EMAIL?.toLowerCase();

export const { handlers, signIn, signOut, auth } = NextAuth({
  providers: [
    GitHub({
      clientId: process.env.GITHUB_ID,
      clientSecret: process.env.GITHUB_SECRET,
    }),
  ],
  pages: {
    signIn: "/login",
  },
  callbacks: {
    async signIn({ user }) {
      if (!allowedEmail) return false;
      const email = user.email?.toLowerCase();
      return email === allowedEmail;
    },
    async session({ session }) {
      return session;
    },
  },
  session: { strategy: "jwt" },
  trustHost: true,
});

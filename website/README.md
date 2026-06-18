# Vicu Website

Simple public website for Alpaca Connect review, built with Next.js, Tailwind CSS, and BaseUI.

## Pages

- `/` - application website
- `/terms` - Terms of Use
- `/privacy` - Privacy Policy
- `/connect/alpaca/callback` - reserved redirect URI route for a future Alpaca Connect OAuth flow

## Development

```bash
npm install
npm run dev
```

Set these before deployment if needed:

```bash
NEXT_PUBLIC_SITE_URL=https://your-domain.example
NEXT_PUBLIC_CONTACT_EMAIL=support@your-domain.example
```

The Terms of Use and Privacy Policy are implementation-ready drafts, but they should still be reviewed by counsel before production use.

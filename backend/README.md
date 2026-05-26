# TelStorage CORS Proxy

A Cloudflare Worker that acts as a CORS proxy for downloading files from Telegram's file API.

## Why This Proxy?

Web browsers block direct downloads from Telegram's file API due to CORS restrictions. This proxy adds the necessary CORS headers to allow your Flutter web app to download files.

## Setup Instructions

### 1. Install Wrangler (Cloudflare CLI)

```bash
npm install -g wrangler
```

### 2. Login to Cloudflare

```bash
wrangler login
```

This will open a browser window to authenticate with your Cloudflare account (free account works fine).

### 3. Deploy the Worker

```bash
cd backend
wrangler deploy
```

After deployment, you'll get a URL like:
```
https://telstorage-proxy.YOUR-SUBDOMAIN.workers.dev
```

### 4. Update Your Flutter App

Copy the worker URL and update `telegram_service.dart`:

```dart
// Replace this line:
final downloadUrl = kIsWeb 
    ? 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(fileUrl)}'
    : fileUrl;

// With your worker URL:
final downloadUrl = kIsWeb 
    ? 'https://telstorage-proxy.YOUR-SUBDOMAIN.workers.dev?url=${Uri.encodeComponent(fileUrl)}'
    : fileUrl;
```

## How It Works

1. Your Flutter web app sends a request to the worker with the Telegram file URL as a parameter
2. The worker fetches the file from Telegram
3. The worker adds CORS headers and returns the file to your app
4. Your app can now download and use the file

## Usage

The worker accepts GET requests with a `url` parameter:

```
https://telstorage-proxy.YOUR-SUBDOMAIN.workers.dev?url=https://api.telegram.org/file/bot.../documents/file.json
```

## Security

- Only allows Telegram file URLs (`https://api.telegram.org/file/`)
- Rejects all other URLs for security
- Free tier: 100,000 requests/day (more than enough for personal use)

## Cost

**FREE** - Cloudflare Workers free tier includes:
- 100,000 requests per day
- 10ms CPU time per request
- Perfect for personal projects

## Troubleshooting

If deployment fails:
1. Make sure you're logged in: `wrangler whoami`
2. Check your Cloudflare account is active
3. Try: `wrangler deploy --legacy-env false`

## Local Testing

Test locally before deploying:

```bash
wrangler dev
```

This starts a local server at `http://localhost:8787`

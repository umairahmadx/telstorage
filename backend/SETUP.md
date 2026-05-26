# Quick Setup Guide

## Step 1: Install Wrangler

Open a terminal and run:

```bash
npm install -g wrangler
```

## Step 2: Login to Cloudflare

```bash
wrangler login
```

- This opens your browser
- Sign up for a free Cloudflare account if you don't have one
- Authorize Wrangler

## Step 3: Deploy

Navigate to the backend folder and deploy:

```bash
cd backend
wrangler deploy
```

You'll see output like:

```
✨ Successfully published your Worker
🌍 https://telstorage-proxy.YOUR-SUBDOMAIN.workers.dev
```

**Copy this URL!** You'll need it in the next step.

## Step 4: Update Flutter App

Open `lib/core/services/telegram_service.dart` and find this line (around line 75):

```dart
final downloadUrl = kIsWeb 
    ? 'https://api.allorigins.win/raw?url=${Uri.encodeComponent(fileUrl)}'
    : fileUrl;
```

Replace it with:

```dart
final downloadUrl = kIsWeb 
    ? 'https://telstorage-proxy.YOUR-SUBDOMAIN.workers.dev?url=${Uri.encodeComponent(fileUrl)}'
    : fileUrl;
```

**Replace `YOUR-SUBDOMAIN` with your actual Cloudflare Workers subdomain!**

## Step 5: Test

1. Run your Flutter web app: `flutter run -d chrome`
2. Try uploading a file
3. It should work without CORS errors! 🎉

## Troubleshooting

**"wrangler: command not found"**
- Make sure Node.js is installed: `node --version`
- Reinstall wrangler: `npm install -g wrangler`

**"Failed to publish"**
- Check you're logged in: `wrangler whoami`
- Try: `wrangler logout` then `wrangler login` again

**Still getting CORS errors**
- Make sure you updated the URL in `telegram_service.dart`
- Clear browser cache and reload
- Check the worker URL is correct (no typos)

## Need Help?

Check the full README.md for more details!

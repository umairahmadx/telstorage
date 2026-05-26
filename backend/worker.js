/**
 * Cloudflare Worker - CORS Proxy for Telegram File Downloads
 * 
 * This worker acts as a proxy to bypass CORS restrictions when downloading
 * files from Telegram's file API in web browsers.
 */

export default {
  async fetch(request, env, ctx) {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
          'Access-Control-Max-Age': '86400',
        },
      });
    }

    // Only allow GET requests
    if (request.method !== 'GET') {
      return new Response('Method not allowed', { status: 405 });
    }

    try {
      // Get the target URL from query parameter
      const url = new URL(request.url);
      const targetUrl = url.searchParams.get('url');

      if (!targetUrl) {
        return new Response('Missing url parameter', { status: 400 });
      }

      // Validate that it's a Telegram file URL
      if (!targetUrl.startsWith('https://api.telegram.org/file/')) {
        return new Response('Invalid URL - only Telegram file URLs are allowed', { 
          status: 403 
        });
      }

      // Fetch the file from Telegram
      const response = await fetch(targetUrl);

      // Create a new response with CORS headers
      const newResponse = new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: {
          ...Object.fromEntries(response.headers),
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      });

      return newResponse;
    } catch (error) {
      return new Response(`Proxy error: ${error.message}`, { 
        status: 500,
        headers: {
          'Access-Control-Allow-Origin': '*',
        },
      });
    }
  },
};

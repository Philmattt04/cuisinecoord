const Anthropic = require('@anthropic-ai/sdk');
const https = require('https');

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
const PLACES_KEY = process.env.GOOGLE_PLACES_KEY || '';

const SYSTEM = `You are CuisineCoord's AI food guide — a friendly, knowledgeable assistant that helps people discover the perfect restaurant nearby.

You have access to the user's location, nearby restaurants, and optionally a selected restaurant with reviews and personal visit history.

Core behaviors:
- Use specific restaurant names from the provided data when making recommendations.
- Be enthusiastic, concise, and helpful. Keep responses to 2-4 sentences unless more detail is needed.
- Always use U.S. customary units (miles, not kilometers; °F, not °C) when discussing distance or temperature.

Time-awareness: When a current date/time is provided, use it to prefer open places, suggest meal-appropriate options (breakfast before noon, dinner after 5 PM), and note if it's a weekend.

Review summaries: When asked to summarize reviews, identify 2-3 recurring positives and 1-2 recurring complaints in bullet format. Be specific — quote phrases from actual reviews where possible.

Comparison mode: When two restaurants are provided (a selected and a compare target), give a clear side-by-side comparison with a direct recommendation. Structure it as: "For [X], [restaurant A] wins. For [Y], [restaurant B] wins. Overall: [recommendation]."

Group decisions: When asked to pick for a group with multiple preferences or restrictions, show your reasoning and explain specifically why the chosen restaurant works for everyone. List any compromises.

Mood-based: When a user describes a mood or occasion (comfort food, date night, quick lunch, healthy), match energy and vibe — not just cuisine type.

Personal history: If the user has visited a restaurant before (shown in visit history), acknowledge it and ask if they'd like to go back or try something new.`;

// ── CORS headers ──────────────────────────────────────────────────────────────

function cors(origin) {
  return {
    'Access-Control-Allow-Origin': origin || '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json',
  };
}

// ── HTTPS fetch helper ────────────────────────────────────────────────────────

function fetchJson(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error(`JSON parse error: ${data.substring(0, 200)}`)); }
      });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

// ── Google Places (New API) ────────────────────────────────────────────────────

const PLACES_BASE = 'places.googleapis.com';

async function nearbySearch(lat, lng, type) {
  const fieldMask = [
    'places.id', 'places.displayName', 'places.location',
    'places.types', 'places.primaryType', 'places.rating',
    'places.userRatingCount', 'places.priceLevel',
    'places.currentOpeningHours', 'places.formattedAddress',
    'places.nationalPhoneNumber', 'places.websiteUri',
  ].join(',');

  const bodyStr = JSON.stringify({
    includedTypes: [type],
    maxResultCount: 20,
    locationRestriction: {
      circle: {
        center: { latitude: lat, longitude: lng },
        radius: 2500,
      },
    },
  });

  const result = await fetchJson({
    hostname: PLACES_BASE,
    path: '/v1/places:searchNearby',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(bodyStr),
      'X-Goog-Api-Key': PLACES_KEY,
      'X-Goog-FieldMask': fieldMask,
    },
  }, bodyStr);
  if (result.error) {
    console.error(`Places API error (${type}):`, JSON.stringify(result.error));
    throw new Error(result.error.message || JSON.stringify(result.error));
  }
  return result;
}

async function placeDetails(placeId) {
  const fieldMask = [
    'id', 'displayName', 'rating', 'userRatingCount', 'priceLevel',
    'reviews', 'formattedAddress', 'nationalPhoneNumber', 'websiteUri',
    'currentOpeningHours',
  ].join(',');

  return fetchJson({
    hostname: PLACES_BASE,
    path: `/v1/places/${encodeURIComponent(placeId)}`,
    method: 'GET',
    headers: {
      'X-Goog-Api-Key': PLACES_KEY,
      'X-Goog-FieldMask': fieldMask,
    },
  }, null);
}

// ── Lambda handler ────────────────────────────────────────────────────────────

exports.handler = async (event) => {
  const origin = event.headers?.origin || '*';
  const c = cors(origin);
  const method = event.requestContext?.http?.method || event.httpMethod || 'POST';
  const path = event.requestContext?.http?.path || event.path || '/';

  if (method === 'OPTIONS') return { statusCode: 200, headers: c, body: '' };
  if (method !== 'POST') return { statusCode: 405, headers: c, body: '{}' };

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return { statusCode: 400, headers: c, body: JSON.stringify({ error: 'Invalid JSON' }) }; }

  // ── /restaurants — Nearby Search ────────────────────────────────────────────
  if (path.endsWith('/restaurants')) {
    const { lat, lng } = body;
    if (!lat || !lng) {
      return { statusCode: 400, headers: c, body: JSON.stringify({ error: 'lat/lng required' }) };
    }
    if (!PLACES_KEY) {
      return { statusCode: 500, headers: c, body: JSON.stringify({ error: 'Places key not configured' }) };
    }
    try {
      const types = ['restaurant', 'cafe', 'bar'];
      const results = await Promise.all(types.map((t) =>
        nearbySearch(lat, lng, t).catch((err) => {
          console.error(`nearbySearch(${t}) error:`, err.message);
          return { places: [], _error: err.message };
        })
      ));
      const seen = new Set();
      const places = [];
      for (const r of results) {
        for (const p of (r.places || [])) {
          if (!seen.has(p.id)) { seen.add(p.id); places.push(p); }
        }
      }
      return { statusCode: 200, headers: c, body: JSON.stringify({ places }) };
    } catch (err) {
      console.error('Places nearby error:', err);
      return { statusCode: 500, headers: c, body: JSON.stringify({ error: err.message }) };
    }
  }

  // ── /place-details — Place Details ──────────────────────────────────────────
  if (path.endsWith('/place-details')) {
    const { placeId } = body;
    if (!placeId) {
      return { statusCode: 400, headers: c, body: JSON.stringify({ error: 'placeId required' }) };
    }
    if (!PLACES_KEY) {
      return { statusCode: 500, headers: c, body: JSON.stringify({ error: 'Places key not configured' }) };
    }
    try {
      const details = await placeDetails(placeId);
      return { statusCode: 200, headers: c, body: JSON.stringify(details) };
    } catch (err) {
      console.error('Places details error:', err);
      return { statusCode: 500, headers: c, body: JSON.stringify({ error: err.message }) };
    }
  }

  // ── /ai — Claude chat ────────────────────────────────────────────────────────
  const { question, location, restaurants, focusedRestaurant,
          compareRestaurant, currentDateTime, history = [] } = body;
  try {
    const parts = [];
    if (currentDateTime) parts.push(`Current date/time: ${currentDateTime}`);
    parts.push(`My location: ${location || 'unknown'}`);
    parts.push(`\nNearby restaurants:\n${restaurants || 'No restaurants loaded yet.'}`);
    if (focusedRestaurant) parts.push(`\n${focusedRestaurant}`);
    if (compareRestaurant) parts.push(`\n${compareRestaurant}`);
    parts.push(`\nMy question: ${question}`);
    const userMessage = parts.join('\n');

    const messages = [
      ...history.map((m) => ({ role: m.role, content: m.content })),
      { role: 'user', content: userMessage },
    ];

    const response = await client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 512,
      system: SYSTEM,
      messages,
    });

    return { statusCode: 200, headers: c, body: JSON.stringify({ content: response.content[0].text }) };
  } catch (err) {
    console.error('Claude error:', err);
    return { statusCode: 500, headers: c, body: JSON.stringify({ error: 'AI request failed' }) };
  }
};

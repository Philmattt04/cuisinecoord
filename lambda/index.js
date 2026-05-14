const Anthropic = require('@anthropic-ai/sdk');

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

const SYSTEM = `You are CuisineCoord's AI food guide — a friendly, knowledgeable assistant that helps people discover the perfect restaurant nearby.

You have access to the user's current location and a list of nearby restaurants. When recommending, use specific restaurant names from the provided data. Be enthusiastic, concise, and helpful.

If asked about cuisine preferences, dietary restrictions, or occasion (date night, family, quick lunch), tailor your recommendations accordingly. Keep responses to 2-3 sentences unless the user asks for more detail.`;

exports.handler = async (event) => {
  const origin = event.headers?.origin || '*';
  const cors = {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json',
  };

  const method = event.requestContext?.http?.method || event.httpMethod || 'POST';
  if (method === 'OPTIONS') return { statusCode: 200, headers: cors, body: '' };
  if (method !== 'POST') return { statusCode: 405, headers: cors, body: '{}' };

  let body;
  try { body = JSON.parse(event.body); }
  catch { return { statusCode: 400, headers: cors, body: JSON.stringify({ error: 'Invalid JSON' }) }; }

  const { question, location, restaurants, history = [] } = body;

  try {
    const userMessage = `My location: ${location || 'unknown'}

Nearby restaurants:
${restaurants || 'No restaurants loaded yet.'}

My question: ${question}`;

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

    return {
      statusCode: 200,
      headers: cors,
      body: JSON.stringify({ content: response.content[0].text }),
    };
  } catch (err) {
    console.error(err);
    return {
      statusCode: 500,
      headers: cors,
      body: JSON.stringify({ error: 'AI request failed' }),
    };
  }
};

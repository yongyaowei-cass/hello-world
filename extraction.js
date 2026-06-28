export function buildExtractionPrompt() {
  return [
    'You are reading a screenshot of a Taobao order page.',
    "Extract each product line item's displayed unit price, its currency, and its quantity.",
    'Also extract the final amount actually paid (labeled something like 实付款).',
    'Respond with ONLY valid JSON, no markdown fences, no commentary, matching exactly this shape:',
    '{"lineItems":[{"name":string,"unitPrice":number,"currency":"CNY"|"SGD","qty":number}],"finalTotal":{"amount":number,"currency":string},"rawCostsSeen":[string]}',
  ].join(' ');
}

export function parseExtractionResponse(rawText) {
  let data;
  try {
    data = JSON.parse(rawText);
  } catch {
    return { error: 'invalid-json' };
  }

  if (!Array.isArray(data.lineItems) || data.lineItems.length === 0) {
    return { error: 'invalid-json' };
  }

  for (const item of data.lineItems) {
    if (
      typeof item.name !== 'string' ||
      typeof item.unitPrice !== 'number' ||
      typeof item.currency !== 'string' ||
      typeof item.qty !== 'number'
    ) {
      return { error: 'invalid-json' };
    }
  }

  if (
    !data.finalTotal ||
    typeof data.finalTotal.amount !== 'number' ||
    typeof data.finalTotal.currency !== 'string'
  ) {
    return { error: 'missing-total' };
  }

  return {
    lineItems: data.lineItems,
    finalTotal: data.finalTotal,
    rawCostsSeen: Array.isArray(data.rawCostsSeen) ? data.rawCostsSeen : [],
  };
}

export async function callVisionApi({ imageBase64, mediaType, apiKey }) {
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'anthropic-dangerous-direct-browser-access': 'true',
    },
    body: JSON.stringify({
      model: 'claude-opus-4-8',
      max_tokens: 1024,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: mediaType, data: imageBase64 } },
            { type: 'text', text: buildExtractionPrompt() },
          ],
        },
      ],
    }),
  });

  if (!response.ok) {
    return { error: 'api-request-failed' };
  }

  const data = await response.json();
  const textBlock = (data.content || []).find((block) => block.type === 'text');

  if (!textBlock) {
    return { error: 'invalid-json' };
  }

  return parseExtractionResponse(textBlock.text);
}

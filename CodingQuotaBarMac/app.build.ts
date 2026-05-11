export default {
  providers: [
    { key: 'zhipu', available: true, envVar: 'Z_AI_API_KEY', baseUrl: 'https://api.z.ai' },
    { key: 'minimax', available: false, envVar: 'MINIMAX_API_KEY', baseUrl: '' },
    { key: 'kimi', available: false, envVar: 'KIMI_API_KEY', baseUrl: '' },
  ],
} as const;

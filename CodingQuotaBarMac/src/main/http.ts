import * as https from 'node:https';
import * as http from 'node:http';
import { URL } from 'node:url';

export interface HttpResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
}

export interface HttpRequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE';
  headers?: Record<string, string>;
  body?: string;
  timeout?: number;
}

export class HttpClient {
  static async request(url: string, options: HttpRequestOptions = {}): Promise<HttpResponse> {
    return new Promise((resolve, reject) => {
      const parsedUrl = new URL(url);
      const isHttps = parsedUrl.protocol === 'https:';
      const client = isHttps ? https : http;

      const reqOptions: http.RequestOptions = {
        hostname: parsedUrl.hostname,
        port: parsedUrl.port || (isHttps ? 443 : 80),
        path: parsedUrl.pathname + parsedUrl.search,
        method: options.method || 'GET',
        headers: options.headers || {},
        timeout: options.timeout || 10000
      };

      const req = client.request(reqOptions, (res) => {
        const chunks: Buffer[] = [];
        res.on('data', (chunk: Buffer) => chunks.push(chunk));
        res.on('end', () => {
          const raw = Buffer.concat(chunks);
          const contentType = res.headers['content-type'] || '';
          const charsetMatch = contentType.match(/charset=([^\s;]+)/i);
          const charset = charsetMatch ? charsetMatch[1].trim().toLowerCase() : 'utf-8';
          let body: string;
          if (charset === 'utf-8' || charset === 'utf8') body = raw.toString('utf-8');
          else {
            const decoder = new TextDecoder(charset);
            body = decoder.decode(raw);
          }
          const headers: Record<string, string> = {};
          for (const [key, value] of Object.entries(res.headers)) {
            headers[key] = Array.isArray(value) ? value.join(', ') : value || '';
          }
          resolve({ status: res.statusCode || 0, headers, body });
        });
      });

      req.on('error', (error) => reject(new Error(`HTTP request failed: ${error.message}`)));
      req.on('timeout', () => { req.destroy(); reject(new Error('HTTP request timeout')); });
      if (options.body) req.write(options.body);
      req.end();
    });
  }

  static async get(url: string, headers?: Record<string, string>): Promise<HttpResponse> {
    return this.request(url, { method: 'GET', headers });
  }

  static async getJson<T = unknown>(url: string, headers?: Record<string, string>): Promise<T> {
    const response = await this.get(url, headers);
    if (response.status >= 400) throw new Error(`HTTP ${response.status}: ${response.body}`);
    return JSON.parse(response.body) as T;
  }
}

export class HttpClientWithRetry {
  constructor(private maxRetries = 3, private retryDelay = 1000) {}
  private delay(ms: number) { return new Promise((resolve) => setTimeout(resolve, ms)); }

  async get(url: string, headers?: Record<string, string>): Promise<HttpResponse> {
    let lastError: Error | null = null;
    for (let attempt = 0; attempt <= this.maxRetries; attempt++) {
      try { return await HttpClient.get(url, headers); }
      catch (error) {
        lastError = error as Error;
        if (attempt < this.maxRetries) await this.delay(this.retryDelay * (attempt + 1));
      }
    }
    throw lastError;
  }

  async getJson<T = unknown>(url: string, headers?: Record<string, string>): Promise<T> {
    const response = await this.get(url, headers);
    if (response.status >= 400) throw new Error(`HTTP ${response.status}: ${response.body}`);
    return JSON.parse(response.body) as T;
  }
}

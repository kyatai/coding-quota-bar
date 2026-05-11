import type { Provider, ProviderConfig } from '../shared/types';
import { ZhipuProvider } from '../providers/zhipu';
import { MiniMaxProvider } from '../providers/minimax';
import { KimiProvider } from '../providers/kimi';
import buildConfig from '../../app.build';

const PROVIDER_CLASSES = { zhipu: ZhipuProvider, minimax: MiniMaxProvider, kimi: KimiProvider } as const;
export type ProviderType = keyof typeof PROVIDER_CLASSES;

export interface LoadedProvider {
  type: ProviderType;
  instance: Provider;
  config: ProviderConfig;
}

export function getAvailableProviderKeys(): string[] {
  return buildConfig.providers.filter(p => p.available).map(p => p.key);
}

export class ProviderLoader {
  static loadProviders(providerConfigs: Record<string, ProviderConfig>): LoadedProvider[] {
    const availableKeys = new Set(getAvailableProviderKeys());
    const loaded: LoadedProvider[] = [];
    for (const [type, config] of Object.entries(providerConfigs)) {
      if (!availableKeys.has(type) || !config.enabled || !config.apiKey?.trim()) continue;
      const ProviderClass = PROVIDER_CLASSES[type as ProviderType];
      if (!ProviderClass) continue;
      try {
        const instance = new ProviderClass();
        const buildEntry = buildConfig.providers.find(p => p.key === type);
        loaded.push({ type: type as ProviderType, instance, config: { ...config, _baseUrl: buildEntry?.baseUrl || '' } });
      } catch (error) {
        console.error(`[Loader] Failed to load provider ${type}:`, error);
      }
    }
    return loaded;
  }
}

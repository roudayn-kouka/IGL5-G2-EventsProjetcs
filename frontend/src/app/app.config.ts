import {
  ApplicationConfig,
  EnvironmentProviders,
  Provider,
  provideBrowserGlobalErrorListeners,
} from '@angular/core';
import { provideHttpClient } from '@angular/common/http';
import { provideRouter } from '@angular/router';
import { API_BASE_URL } from './core/api-base-url';
import { routes } from './app.routes';

export function appConfig(apiBaseUrl = '/events'): ApplicationConfig {
  const providers: (Provider | EnvironmentProviders)[] = [
    provideBrowserGlobalErrorListeners(),
    provideHttpClient(),
    provideRouter(routes),
    { provide: API_BASE_URL, useValue: apiBaseUrl },
  ];
  return { providers };
}

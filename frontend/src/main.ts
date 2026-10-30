import { bootstrapApplication } from '@angular/platform-browser';
import { AppComponent } from './app/app';
import { appConfig } from './app/app.config';

interface RuntimeConfig {
  apiBaseUrl?: string;
}

async function start(): Promise<void> {
  let runtimeConfig: RuntimeConfig = {};
  try {
    const response = await fetch('/runtime-config.json', { cache: 'no-store' });
    if (response.ok) {
      runtimeConfig = (await response.json()) as RuntimeConfig;
    }
  } catch {
    // The default same-origin /events path remains available if the optional file is absent.
  }

  await bootstrapApplication(AppComponent, appConfig(runtimeConfig.apiBaseUrl));
}

void start();

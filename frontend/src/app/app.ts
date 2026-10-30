import { Component } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  template: `
    <div class="app-layout">
      <header class="navbar">
        <a class="brand" routerLink="/logistics">
          <span class="brand-logo">E</span>
          <span class="brand-text">
            <strong>EventsFST</strong>
            <small>Event Management Platform</small>
          </span>
        </a>

        <nav class="navigation">
          <a routerLink="/logistics" routerLinkActive="active"
             [routerLinkActiveOptions]="{ exact: true }">
            <span class="nav-icon">▦</span>
            Logistiques
          </a>
          <a routerLink="/stats" routerLinkActive="active">
            <span class="nav-icon">▥</span>
            Statistiques
          </a>
        </nav>

        <div class="profile">
          <span class="profile-avatar">A</span>
          <span>Administration</span>
        </div>
      </header>

      <main class="main-content">
        <router-outlet></router-outlet>
      </main>

      <footer class="footer">
        EventsFST · FST · IGL5-G2
      </footer>
    </div>
  `,
  styleUrl: './app.scss'
})
export class App {}

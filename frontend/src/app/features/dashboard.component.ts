import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  inject,
  signal,
} from '@angular/core';
import { RouterLink } from '@angular/router';
import { DecimalPipe } from '@angular/common';
import { forkJoin } from 'rxjs';
import { EventsApiService } from '../core/events-api.service';
import { apiErrorMessage } from '../core/api-error';
import { EventStats, GlobalStats, TACHE_LABELS, Tache } from '../core/models';

interface TaskItem {
  label: string;
  count: number;
  pct: number;
  color: string;
}

const TASK_COLORS: Record<string, string> = {
  INVITE: '#0ea5e9',
  ORGANISATEUR: '#8b5cf6',
  SERVEUR: '#f59e0b',
  ANIMATEUR: '#10b981',
};

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [RouterLink, DecimalPipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="dashboard">
      <div class="page-header">
        <h1>Dashboard</h1>
        <p class="subtitle">Live overview of events, participants and logistics</p>
      </div>

      @if (error()) {
        <div class="alert alert-error" role="alert">
          <span class="alert-icon">⚠</span>
          <span>{{ error() }}</span>
          <button class="btn-retry" (click)="load()">Retry</button>
        </div>
      }

      @if (loading()) {
        <div class="kpi-grid">
          @for (_ of skeletons; track $index) {
            <div class="kpi-card skeleton"></div>
          }
        </div>
        <div class="section-skeleton"></div>
      }

      @if (!loading() && summary()) {
        <!-- KPI row -->
        <div class="kpi-grid">
          <div class="kpi-card kpi-blue">
            <div class="kpi-icon">📅</div>
            <div class="kpi-body">
              <div class="kpi-value">{{ summary()!.nbEvents }}</div>
              <div class="kpi-label">Total Events</div>
            </div>
          </div>
          <div class="kpi-card kpi-teal">
            <div class="kpi-icon">🔜</div>
            <div class="kpi-body">
              <div class="kpi-value">{{ summary()!.nbEventsAVenir }}</div>
              <div class="kpi-label">Upcoming</div>
            </div>
          </div>
          <div class="kpi-card kpi-purple">
            <div class="kpi-icon">👥</div>
            <div class="kpi-body">
              <div class="kpi-value">{{ summary()!.nbParticipants }}</div>
              <div class="kpi-label">Participants</div>
            </div>
          </div>
          <div class="kpi-card kpi-amber">
            <div class="kpi-icon">📦</div>
            <div class="kpi-body">
              <div class="kpi-value">
                {{ summary()!.nbLogisticsReservees }}<span class="kpi-denom">/{{ summary()!.nbLogistics }}</span>
              </div>
              <div class="kpi-label">Logistics Reserved</div>
            </div>
          </div>
          <div class="kpi-card kpi-emerald">
            <div class="kpi-icon">💶</div>
            <div class="kpi-body">
              <div class="kpi-value">
                {{ summary()!.coutTotalLogistiqueReservee | number:'1.0-0' }}<span class="kpi-unit"> DT</span>
              </div>
              <div class="kpi-label">Reserved Cost</div>
            </div>
          </div>
        </div>

        <!-- Reservation rate -->
        <div class="rate-bar-card">
          <div class="rate-bar-header">
            <span class="rate-bar-title">Logistics reservation rate</span>
            <span class="rate-bar-pct">{{ summary()!.tauxReservation | number:'1.0-1' }}%</span>
          </div>
          <div class="rate-bar-track">
            <div class="rate-bar-fill" [style.width.%]="summary()!.tauxReservation"></div>
          </div>
        </div>

        <!-- Role breakdown -->
        @if (taskBreakdown().length > 0) {
          <div class="breakdown-card">
            <h2 class="section-title">Participants by Role</h2>
            <div class="breakdown-grid">
              @for (item of taskBreakdown(); track item.label) {
                <div class="breakdown-item">
                  <div class="breakdown-bar-row">
                    <span class="breakdown-label">{{ item.label }}</span>
                    <span class="breakdown-count">{{ item.count }}</span>
                  </div>
                  <div class="breakdown-track">
                    <div
                      class="breakdown-fill"
                      [style.width.%]="item.pct"
                      [style.background]="item.color"
                    ></div>
                  </div>
                </div>
              }
            </div>
          </div>
        }
      }

      <!-- Events grid -->
      @if (!loading() && events().length > 0) {
        <div class="events-section">
          <div class="section-header">
            <h2 class="section-title">Events</h2>
            <a routerLink="/events" class="link-all">View all →</a>
          </div>
          <div class="events-grid">
            @for (ev of events(); track ev.idEvent) {
              <a [routerLink]="['/events', ev.idEvent]" class="event-card">
                <div class="event-card-top">
                  <span class="event-name">{{ ev.description }}</span>
                  @if (ev.averageRating > 0) {
                    <span class="rating-badge">★ {{ ev.averageRating | number:'1.1-1' }}</span>
                  } @else {
                    <span class="rating-badge rating-none">No reviews</span>
                  }
                </div>
                <div class="event-meta">
                  <span class="meta-item">📅 {{ ev.dateDebut }} – {{ ev.dateFin }}</span>
                  <span class="meta-item badge-neutral">{{ ev.dureeJours }}d</span>
                </div>
                <div class="event-stats-row">
                  <span class="stat-chip chip-blue">👥 {{ ev.nbParticipants }}</span>
                  <span class="stat-chip chip-amber">📦 {{ ev.nbLogisticsReservees }}/{{ ev.nbLogistics }}</span>
                  <span class="stat-chip chip-emerald">{{ ev.coutLogistiqueReservee | number:'1.0-0' }} DT</span>
                </div>
              </a>
            }
          </div>
        </div>
      }

      @if (!loading() && !error() && events().length === 0) {
        <div class="empty-state">
          <div class="empty-icon">📭</div>
          <p>No events found.</p>
        </div>
      }
    </div>
  `,
  styles: [`
    .dashboard { display: flex; flex-direction: column; gap: 28px; }

    .page-header { margin-bottom: 4px; }
    .page-header h1 { font-size: 2rem; font-weight: 800; color: #0f172a; margin: 0 0 6px; }
    .subtitle { color: #64748b; margin: 0; font-size: .95rem; }

    .alert { display: flex; align-items: center; gap: 12px; padding: 14px 18px; border-radius: 12px; font-size: .9rem; }
    .alert-error { background: #fef2f2; border: 1px solid #fecaca; color: #991b1b; }
    .alert-icon { font-size: 1.1rem; }
    .btn-retry { margin-left: auto; background: #dc2626; color: #fff; border: none; border-radius: 8px; padding: 6px 14px; font-size: .85rem; cursor: pointer; transition: background .2s; }
    .btn-retry:hover { background: #b91c1c; }

    .kpi-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 16px; }
    .kpi-card {
      border-radius: 18px; padding: 20px 22px; display: flex; align-items: center; gap: 16px;
      box-shadow: 0 1px 3px rgba(0,0,0,.06), 0 4px 16px rgba(0,0,0,.04);
      transition: transform .25s, box-shadow .25s;
    }
    .kpi-card:hover { transform: translateY(-4px); box-shadow: 0 6px 24px rgba(0,0,0,.1); }
    .kpi-blue    { background: linear-gradient(135deg, #eff6ff 0%, #dbeafe 100%); }
    .kpi-teal    { background: linear-gradient(135deg, #f0fdfa 0%, #ccfbf1 100%); }
    .kpi-purple  { background: linear-gradient(135deg, #faf5ff 0%, #ede9fe 100%); }
    .kpi-amber   { background: linear-gradient(135deg, #fffbeb 0%, #fef3c7 100%); }
    .kpi-emerald { background: linear-gradient(135deg, #ecfdf5 0%, #d1fae5 100%); }
    .kpi-icon { font-size: 2rem; flex-shrink: 0; }
    .kpi-value { font-size: 1.9rem; font-weight: 800; color: #0f172a; line-height: 1; }
    .kpi-denom, .kpi-unit { font-size: 1rem; font-weight: 500; color: #64748b; }
    .kpi-label { font-size: .75rem; font-weight: 700; color: #64748b; margin-top: 5px; text-transform: uppercase; letter-spacing: .05em; }

    .skeleton { min-height: 90px; background: linear-gradient(90deg,#f1f5f9 25%,#e2e8f0 50%,#f1f5f9 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
    .section-skeleton { height: 260px; border-radius: 18px; background: linear-gradient(90deg,#f1f5f9 25%,#e2e8f0 50%,#f1f5f9 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; }
    @keyframes shimmer { 0%{background-position:200% 0} 100%{background-position:-200% 0} }

    .rate-bar-card { background: #fff; border-radius: 18px; padding: 20px 24px; box-shadow: 0 1px 3px rgba(0,0,0,.06); }
    .rate-bar-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }
    .rate-bar-title { font-weight: 600; color: #374151; }
    .rate-bar-pct { font-size: 1.15rem; font-weight: 800; color: #0ea5e9; }
    .rate-bar-track { height: 12px; background: #e2e8f0; border-radius: 999px; overflow: hidden; }
    .rate-bar-fill { height: 100%; background: linear-gradient(90deg,#06b6d4,#0ea5e9); border-radius: 999px; transition: width .7s ease; }

    .breakdown-card { background: #fff; border-radius: 18px; padding: 22px 24px; box-shadow: 0 1px 3px rgba(0,0,0,.06); }
    .breakdown-grid { display: flex; flex-direction: column; gap: 16px; margin-top: 18px; }
    .breakdown-bar-row { display: flex; justify-content: space-between; margin-bottom: 6px; }
    .breakdown-label { font-size: .88rem; font-weight: 600; color: #374151; }
    .breakdown-count { font-size: .88rem; font-weight: 700; color: #0f172a; }
    .breakdown-track { height: 8px; background: #f1f5f9; border-radius: 999px; overflow: hidden; }
    .breakdown-fill { height: 100%; border-radius: 999px; transition: width .7s ease; }

    .events-section { display: flex; flex-direction: column; gap: 0; }
    .section-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px; }
    .section-title { font-size: 1.2rem; font-weight: 700; color: #0f172a; margin: 0; }
    .link-all { color: #0ea5e9; font-weight: 600; text-decoration: none; font-size: .88rem; }
    .link-all:hover { text-decoration: underline; }

    .events-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(290px, 1fr)); gap: 16px; }
    .event-card {
      background: #fff; border-radius: 18px; padding: 20px; text-decoration: none; color: inherit;
      box-shadow: 0 1px 3px rgba(0,0,0,.06); border: 1.5px solid transparent;
      display: flex; flex-direction: column; gap: 12px;
      transition: transform .22s, box-shadow .22s, border-color .22s;
    }
    .event-card:hover { transform: translateY(-4px); box-shadow: 0 8px 28px rgba(14,165,233,.13); border-color: #bae6fd; }
    .event-card-top { display: flex; justify-content: space-between; align-items: flex-start; gap: 10px; }
    .event-name { font-weight: 700; font-size: 1rem; color: #0f172a; flex: 1; }
    .rating-badge { background: #fef3c7; color: #92400e; font-size: .78rem; font-weight: 700; padding: 3px 10px; border-radius: 999px; white-space: nowrap; }
    .rating-none { background: #f1f5f9; color: #94a3b8; }
    .event-meta { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
    .meta-item { font-size: .82rem; color: #64748b; }
    .badge-neutral { background: #f1f5f9; color: #64748b; font-size: .76rem; font-weight: 600; padding: 2px 8px; border-radius: 6px; }
    .event-stats-row { display: flex; gap: 8px; flex-wrap: wrap; }
    .stat-chip { font-size: .78rem; font-weight: 600; padding: 4px 10px; border-radius: 8px; }
    .chip-blue   { background: #dbeafe; color: #1e40af; }
    .chip-amber  { background: #fef3c7; color: #92400e; }
    .chip-emerald{ background: #d1fae5; color: #065f46; }

    .empty-state { text-align: center; padding: 64px 24px; color: #94a3b8; }
    .empty-icon { font-size: 3rem; margin-bottom: 12px; }

    @media (max-width: 640px) {
      .kpi-grid { grid-template-columns: 1fr 1fr; }
      .events-grid { grid-template-columns: 1fr; }
      .page-header h1 { font-size: 1.6rem; }
    }
  `],
})
export class DashboardComponent implements OnInit {
  readonly loading = signal(true);
  readonly error = signal<string | null>(null);
  readonly summary = signal<GlobalStats | null>(null);
  readonly events = signal<EventStats[]>([]);
  readonly taskBreakdown = signal<TaskItem[]>([]);
  readonly skeletons = [1, 2, 3, 4, 5];

  private readonly eventsApi = inject(EventsApiService);

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading.set(true);
    this.error.set(null);

    forkJoin({
      summary: this.eventsApi.getSummary(),
      events: this.eventsApi.getEvents(),
    }).subscribe({
      next: ({ summary, events }) => {
        this.summary.set(summary);
        this.events.set(events);
        this.buildBreakdown(summary);
        this.loading.set(false);
      },
      error: (err: unknown) => {
        this.error.set(apiErrorMessage(err, 'Failed to load dashboard data.'));
        this.loading.set(false);
      },
    });
  }

  private buildBreakdown(summary: GlobalStats): void {
    const tasks = summary.participantsParTache ?? {};
    const total = (Object.values(tasks) as number[]).reduce((a, b) => a + (b ?? 0), 0) || 1;
    const items: TaskItem[] = (Object.entries(tasks) as [Tache, number][]).map(
      ([key, count]) => ({
        label: TACHE_LABELS[key] ?? key,
        count: count ?? 0,
        pct: ((count ?? 0) / total) * 100,
        color: TASK_COLORS[key] ?? '#94a3b8',
      })
    );
    this.taskBreakdown.set(items);
  }
}

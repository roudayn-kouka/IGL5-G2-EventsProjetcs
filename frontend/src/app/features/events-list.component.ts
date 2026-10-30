import {
  ChangeDetectionStrategy,
  Component,
  OnInit,
  computed,
  inject,
  signal,
} from '@angular/core';
import { RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { DecimalPipe } from '@angular/common';
import { EventsApiService } from '../core/events-api.service';
import { apiErrorMessage } from '../core/api-error';
import { EventStats } from '../core/models';

type FilterMode = 'all' | 'upcoming' | 'past';

@Component({
  selector: 'app-events-list',
  standalone: true,
  imports: [RouterLink, FormsModule, DecimalPipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="events-list-page">
      <!-- Header -->
      <div class="page-header">
        <div>
          <h1>Events</h1>
          <p class="subtitle">{{ filteredEvents().length }} event{{ filteredEvents().length !== 1 ? 's' : '' }} found</p>
        </div>
      </div>

      <!-- Toolbar -->
      <div class="toolbar">
        <div class="search-box">
          <span class="search-icon">🔍</span>
          <input
            id="events-search"
            type="search"
            placeholder="Search events…"
            [(ngModel)]="searchQuery"
            (ngModelChange)="onSearch()"
            class="search-input"
            aria-label="Search events"
          />
          @if (searchQuery()) {
            <button class="search-clear" (click)="clearSearch()" aria-label="Clear search">✕</button>
          }
        </div>
        <div class="filter-tabs" role="group" aria-label="Event filter">
          @for (tab of filterTabs; track tab.value) {
            <button
              [class.active]="filterMode() === tab.value"
              (click)="setFilter(tab.value)"
              class="filter-tab"
            >{{ tab.label }}</button>
          }
        </div>
      </div>

      <!-- Error -->
      @if (error()) {
        <div class="alert alert-error" role="alert">
          <span>⚠ {{ error() }}</span>
          <button class="btn-retry" (click)="load()">Retry</button>
        </div>
      }

      <!-- Skeletons -->
      @if (loading()) {
        <div class="events-grid">
          @for (_ of skeletons; track $index) {
            <div class="event-card skeleton"></div>
          }
        </div>
      }

      <!-- Event cards -->
      @if (!loading() && filteredEvents().length > 0) {
        <div class="events-grid">
          @for (ev of filteredEvents(); track ev.idEvent) {
            <a [routerLink]="['/events', ev.idEvent]" class="event-card">
              <div class="card-header">
                <div class="event-id">Event #{{ ev.idEvent }}</div>
                @if (isUpcoming(ev)) {
                  <span class="status-badge status-upcoming">Upcoming</span>
                } @else {
                  <span class="status-badge status-past">Past</span>
                }
              </div>

              <h3 class="event-title">{{ ev.description }}</h3>

              <div class="event-dates">
                <span class="date-range">
                  📅 <strong>{{ ev.dateDebut }}</strong> → <strong>{{ ev.dateFin }}</strong>
                </span>
                <span class="duration-badge">{{ ev.dureeJours }}d</span>
              </div>

              <div class="divider"></div>

              <div class="stats-grid">
                <div class="stat-box">
                  <div class="stat-icon">👥</div>
                  <div class="stat-val">{{ ev.nbParticipants }}</div>
                  <div class="stat-lbl">Participants</div>
                </div>
                <div class="stat-box">
                  <div class="stat-icon">📦</div>
                  <div class="stat-val">{{ ev.nbLogisticsReservees }}<span class="stat-denom">/{{ ev.nbLogistics }}</span></div>
                  <div class="stat-lbl">Reserved</div>
                </div>
                <div class="stat-box">
                  <div class="stat-icon">💶</div>
                  <div class="stat-val">{{ ev.coutLogistiqueReservee | number:'1.0-0' }}</div>
                  <div class="stat-lbl">Cost (DT)</div>
                </div>
                <div class="stat-box">
                  <div class="stat-icon">⭐</div>
                  @if (ev.averageRating > 0) {
                    <div class="stat-val">{{ ev.averageRating | number:'1.1-1' }}</div>
                  } @else {
                    <div class="stat-val stat-none">—</div>
                  }
                  <div class="stat-lbl">Rating</div>
                </div>
              </div>

              <div class="card-footer">
                <span class="view-link">View details →</span>
              </div>
            </a>
          }
        </div>
      }

      <!-- Empty -->
      @if (!loading() && !error() && filteredEvents().length === 0) {
        <div class="empty-state">
          <div class="empty-icon">🔎</div>
          <p>
            @if (searchQuery()) {
              No events match "<strong>{{ searchQuery() }}</strong>"
            } @else {
              No events in this category.
            }
          </p>
          @if (searchQuery()) {
            <button class="btn-clear" (click)="clearSearch()">Clear search</button>
          }
        </div>
      }
    </div>
  `,
  styles: [`
    .events-list-page { display: flex; flex-direction: column; gap: 24px; }

    .page-header { display: flex; justify-content: space-between; align-items: flex-start; }
    .page-header h1 { font-size: 2rem; font-weight: 800; color: #0f172a; margin: 0 0 6px; }
    .subtitle { color: #64748b; margin: 0; font-size: .9rem; }

    /* Toolbar */
    .toolbar { display: flex; gap: 16px; flex-wrap: wrap; align-items: center; }
    .search-box { position: relative; flex: 1; min-width: 220px; }
    .search-icon { position: absolute; left: 12px; top: 50%; transform: translateY(-50%); font-size: .95rem; pointer-events: none; }
    .search-input {
      width: 100%; padding: 10px 36px 10px 38px; border: 1.5px solid #e2e8f0; border-radius: 12px;
      font-size: .92rem; background: #fff; color: #0f172a; outline: none; transition: border-color .2s, box-shadow .2s;
    }
    .search-input:focus { border-color: #0ea5e9; box-shadow: 0 0 0 3px rgba(14,165,233,.12); }
    .search-clear { position: absolute; right: 10px; top: 50%; transform: translateY(-50%); background: none; border: none; color: #94a3b8; cursor: pointer; font-size: 1rem; padding: 2px 4px; }
    .search-clear:hover { color: #64748b; }

    .filter-tabs { display: flex; background: #f1f5f9; border-radius: 12px; padding: 4px; gap: 2px; }
    .filter-tab { background: transparent; border: none; border-radius: 9px; padding: 7px 16px; font-size: .86rem; font-weight: 600; color: #64748b; cursor: pointer; transition: background .15s, color .15s; }
    .filter-tab.active { background: #fff; color: #0f172a; box-shadow: 0 1px 4px rgba(0,0,0,.08); }
    .filter-tab:hover:not(.active) { color: #0f172a; }

    /* Alert */
    .alert { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 18px; border-radius: 12px; font-size: .9rem; }
    .alert-error { background: #fef2f2; border: 1px solid #fecaca; color: #991b1b; }
    .btn-retry { background: #dc2626; color: #fff; border: none; border-radius: 8px; padding: 6px 14px; font-size: .85rem; cursor: pointer; }
    .btn-retry:hover { background: #b91c1c; }

    /* Grid */
    .events-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 18px; }

    /* Card */
    .event-card {
      background: #fff; border-radius: 20px; padding: 22px; text-decoration: none; color: inherit;
      box-shadow: 0 1px 3px rgba(0,0,0,.06), 0 2px 8px rgba(0,0,0,.04);
      border: 1.5px solid transparent; display: flex; flex-direction: column; gap: 12px;
      transition: transform .22s, box-shadow .22s, border-color .22s;
    }
    .event-card:hover { transform: translateY(-4px); box-shadow: 0 10px 30px rgba(14,165,233,.14); border-color: #bae6fd; }

    .card-header { display: flex; justify-content: space-between; align-items: center; }
    .event-id { font-size: .75rem; font-weight: 700; color: #94a3b8; text-transform: uppercase; letter-spacing: .06em; }

    .status-badge { font-size: .73rem; font-weight: 700; padding: 3px 10px; border-radius: 999px; text-transform: uppercase; letter-spacing: .04em; }
    .status-upcoming { background: #d1fae5; color: #065f46; }
    .status-past    { background: #f1f5f9; color: #64748b; }

    .event-title { font-size: 1.05rem; font-weight: 700; color: #0f172a; margin: 0; line-height: 1.4; }

    .event-dates { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 6px; }
    .date-range { font-size: .82rem; color: #64748b; }
    .duration-badge { background: #f1f5f9; color: #64748b; font-size: .76rem; font-weight: 700; padding: 2px 8px; border-radius: 6px; }

    .divider { border: none; border-top: 1px solid #f1f5f9; margin: 0; }

    .stats-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 4px; }
    .stat-box { text-align: center; padding: 8px 4px; }
    .stat-icon { font-size: 1rem; margin-bottom: 4px; }
    .stat-val { font-size: 1.05rem; font-weight: 800; color: #0f172a; }
    .stat-denom { font-size: .8rem; font-weight: 500; color: #94a3b8; }
    .stat-none { color: #cbd5e1; }
    .stat-lbl { font-size: .68rem; font-weight: 600; color: #94a3b8; text-transform: uppercase; letter-spacing: .04em; margin-top: 2px; }

    .card-footer { display: flex; justify-content: flex-end; }
    .view-link { font-size: .82rem; font-weight: 700; color: #0ea5e9; }

    .skeleton { min-height: 240px; background: linear-gradient(90deg,#f1f5f9 25%,#e2e8f0 50%,#f1f5f9 75%); background-size: 200% 100%; animation: shimmer 1.4s infinite; border-radius: 20px; }
    @keyframes shimmer { 0%{background-position:200% 0} 100%{background-position:-200% 0} }

    .empty-state { text-align: center; padding: 72px 24px; color: #94a3b8; }
    .empty-icon { font-size: 3rem; margin-bottom: 14px; }
    .empty-state p { font-size: 1rem; color: #64748b; }
    .btn-clear { margin-top: 12px; background: #f1f5f9; border: none; border-radius: 10px; padding: 9px 20px; font-size: .88rem; font-weight: 600; color: #374151; cursor: pointer; transition: background .2s; }
    .btn-clear:hover { background: #e2e8f0; }

    @media (max-width: 640px) {
      .toolbar { flex-direction: column; align-items: stretch; }
      .events-grid { grid-template-columns: 1fr; }
      .page-header h1 { font-size: 1.6rem; }
    }
  `],
})
export class EventsListComponent implements OnInit {
  readonly loading = signal(true);
  readonly error = signal<string | null>(null);
  readonly allEvents = signal<EventStats[]>([]);
  readonly searchQuery = signal('');
  readonly filterMode = signal<FilterMode>('all');
  readonly skeletons = [1, 2, 3, 4, 5, 6];

  readonly filterTabs: { label: string; value: FilterMode }[] = [
    { label: 'All', value: 'all' },
    { label: 'Upcoming', value: 'upcoming' },
    { label: 'Past', value: 'past' },
  ];

  readonly filteredEvents = computed<EventStats[]>(() => {
    const q = this.searchQuery().toLowerCase().trim();
    const mode = this.filterMode();
    const today = new Date().toISOString().slice(0, 10);

    return this.allEvents().filter(ev => {
      const matchesSearch = !q || ev.description.toLowerCase().includes(q);
      const upcoming = ev.dateFin >= today;
      const matchesFilter =
        mode === 'all' ||
        (mode === 'upcoming' && upcoming) ||
        (mode === 'past' && !upcoming);
      return matchesSearch && matchesFilter;
    });
  });

  private readonly eventsApi = inject(EventsApiService);

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.loading.set(true);
    this.error.set(null);
    this.eventsApi.getEvents().subscribe({
      next: events => {
        this.allEvents.set(events);
        this.loading.set(false);
      },
      error: (err: unknown) => {
        this.error.set(apiErrorMessage(err, 'Failed to load events.'));
        this.loading.set(false);
      },
    });
  }

  onSearch(): void {
    // searchQuery signal is already updated by [(ngModel)]
  }

  clearSearch(): void {
    this.searchQuery.set('');
  }

  setFilter(mode: FilterMode): void {
    this.filterMode.set(mode);
  }

  isUpcoming(ev: EventStats): boolean {
    const today = new Date().toISOString().slice(0, 10);
    return ev.dateFin >= today;
  }
}

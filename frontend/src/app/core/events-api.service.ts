import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { API_BASE_URL } from './api-base-url';
import { EventStats, GlobalStats } from './models';

@Injectable({ providedIn: 'root' })
export class EventsApiService {
  private readonly http = inject(HttpClient);
  private readonly base = inject(API_BASE_URL).replace(/\/$/, '');

  getSummary(): Observable<GlobalStats> {
    return this.http.get<GlobalStats>(`${this.base}/event-stats/summary`);
  }

  getEvents(): Observable<EventStats[]> {
    return this.http.get<EventStats[]>(`${this.base}/event-stats`);
  }

  getEvent(id: number): Observable<EventStats> {
    return this.http.get<EventStats>(`${this.base}/event-stats/${id}`);
  }

  getUpcoming(): Observable<EventStats[]> {
    return this.http.get<EventStats[]>(`${this.base}/event-stats/upcoming`);
  }

  getBetween(d1: string, d2: string): Observable<EventStats[]> {
    return this.http.get<EventStats[]>(`${this.base}/event-stats/between/${d1}/${d2}`);
  }
}

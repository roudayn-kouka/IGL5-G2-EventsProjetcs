import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { API_BASE_URL } from './api-base-url';
import { Logistics } from './models';

@Injectable({ providedIn: 'root' })
export class LogisticsApiService {
  private readonly http = inject(HttpClient);
  private readonly base = inject(API_BASE_URL).replace(/\/$/, '');

  getAll(): Observable<Logistics[]> {
    return this.http.get<Logistics[]>(`${this.base}/logistics`);
  }

  getById(id: number): Observable<Logistics> {
    return this.http.get<Logistics>(`${this.base}/logistics/${id}`);
  }

  getReserved(): Observable<Logistics[]> {
    return this.http.get<Logistics[]>(`${this.base}/logistics/reserved`);
  }

  getCoutTotal(id: number): Observable<number> {
    return this.http.get<number>(`${this.base}/logistics/${id}/cout`);
  }

  create(logistics: Omit<Logistics, 'idLog'>): Observable<Logistics> {
    return this.http.post<Logistics>(`${this.base}/logistics`, logistics);
  }

  update(logistics: Logistics): Observable<Logistics> {
    return this.http.put<Logistics>(`${this.base}/logistics`, logistics);
  }

  delete(id: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/logistics/${id}`);
  }
}

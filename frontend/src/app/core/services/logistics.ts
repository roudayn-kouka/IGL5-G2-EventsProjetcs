import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Logistics } from '../../models/logistics.model';

@Injectable({
  providedIn: 'root'
})
export class LogisticsService {
  private http = inject(HttpClient);
  private apiUrl = 'http://localhost:8089/events/logistics';

  getAll(): Observable<Logistics[]> {
    return this.http.get<Logistics[]>(this.apiUrl);
  }

  getById(id: number): Observable<Logistics> {
    return this.http.get<Logistics>(`${this.apiUrl}/${id}`);
  }

  getReserved(): Observable<Logistics[]> {
    return this.http.get<Logistics[]>(`${this.apiUrl}/reserved`);
  }

  add(data: Logistics): Observable<Logistics> {
    return this.http.post<Logistics>(this.apiUrl, data);
  }

  update(data: Logistics): Observable<Logistics> {
    return this.http.put<Logistics>(this.apiUrl, data);
  }

  delete(id: number): Observable<void> {
    return this.http.delete<void>(`${this.apiUrl}/${id}`);
  }

  getTotalCost(id: number): Observable<number> {
    return this.http.get<number>(`${this.apiUrl}/${id}/cout`);
  }
}


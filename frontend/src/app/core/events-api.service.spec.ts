import { TestBed } from '@angular/core/testing';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { provideHttpClient } from '@angular/common/http';
import { EventsApiService } from './events-api.service';
import { API_BASE_URL } from './api-base-url';
import { EventStats, GlobalStats } from './models';

const BASE = 'http://localhost:8089/events';

describe('EventsApiService', () => {
  let service: EventsApiService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: API_BASE_URL, useValue: BASE },
        EventsApiService,
      ],
    });
    service = TestBed.inject(EventsApiService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  it('getSummary() should call GET /event-stats/summary', () => {
    const mock: GlobalStats = {
      nbEvents: 3,
      nbEventsAVenir: 1,
      nbParticipants: 10,
      nbLogistics: 5,
      nbLogisticsReservees: 3,
      tauxReservation: 60,
      coutTotalLogistiqueReservee: 1200,
      participantsParTache: {},
    };
    service.getSummary().subscribe(result => expect(result).toEqual(mock));
    const req = httpMock.expectOne(`${BASE}/event-stats/summary`);
    expect(req.request.method).toBe('GET');
    req.flush(mock);
  });

  it('getEvents() should call GET /event-stats', () => {
    const mock: EventStats[] = [];
    service.getEvents().subscribe(result => expect(result).toEqual(mock));
    const req = httpMock.expectOne(`${BASE}/event-stats`);
    expect(req.request.method).toBe('GET');
    req.flush(mock);
  });

  it('getEvent(id) should call GET /event-stats/:id', () => {
    const mock = { idEvent: 42 } as EventStats;
    service.getEvent(42).subscribe(result => expect(result).toEqual(mock));
    const req = httpMock.expectOne(`${BASE}/event-stats/42`);
    expect(req.request.method).toBe('GET');
    req.flush(mock);
  });

  it('getUpcoming() should call GET /event-stats/upcoming', () => {
    service.getUpcoming().subscribe();
    const req = httpMock.expectOne(`${BASE}/event-stats/upcoming`);
    expect(req.request.method).toBe('GET');
    req.flush([]);
  });

  it('getBetween() should call GET /event-stats/between/:d1/:d2', () => {
    service.getBetween('2025-01-01', '2025-12-31').subscribe();
    const req = httpMock.expectOne(`${BASE}/event-stats/between/2025-01-01/2025-12-31`);
    expect(req.request.method).toBe('GET');
    req.flush([]);
  });
});

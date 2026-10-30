import { TestBed } from '@angular/core/testing';
import {
  HttpTestingController,
  provideHttpClientTesting,
} from '@angular/common/http/testing';
import { provideHttpClient } from '@angular/common/http';
import { FeedbackApiService } from './feedback-api.service';
import { API_BASE_URL } from './api-base-url';
import { Feedback, FeedbackAverage } from './models';

const BASE = 'http://localhost:8089/events';

describe('FeedbackApiService', () => {
  let service: FeedbackApiService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: API_BASE_URL, useValue: BASE },
        FeedbackApiService,
      ],
    });
    service = TestBed.inject(FeedbackApiService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  it('getForEvent(id) should call GET /feedback/event/:id', () => {
    const mock: Feedback[] = [];
    service.getForEvent(1).subscribe(r => expect(r).toEqual(mock));
    const req = httpMock.expectOne(`${BASE}/feedback/event/1`);
    expect(req.request.method).toBe('GET');
    req.flush(mock);
  });

  it('getAverage(id) should call GET /feedback/event/:id/moyenne', () => {
    const mock: FeedbackAverage = { eventId: 1, averageRating: 4.2, totalFeedbacks: 5 };
    service.getAverage(1).subscribe(r => expect(r).toEqual(mock));
    const req = httpMock.expectOne(`${BASE}/feedback/event/1/moyenne`);
    expect(req.request.method).toBe('GET');
    req.flush(mock);
  });

  it('create() should call POST /feedback/:eventId/:participantId', () => {
    service.create(1, 2, { note: 5 }).subscribe();
    const req = httpMock.expectOne(`${BASE}/feedback/1/2`);
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({ note: 5 });
    req.flush({ id: 99 });
  });

  it('delete(id) should call DELETE /feedback/:id', () => {
    service.delete(7).subscribe();
    const req = httpMock.expectOne(`${BASE}/feedback/7`);
    expect(req.request.method).toBe('DELETE');
    req.flush(null);
  });
});

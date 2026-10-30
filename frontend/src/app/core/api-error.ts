import { HttpErrorResponse } from '@angular/common/http';

interface ApiErrorBody {
  message?: string;
}

export function apiErrorMessage(error: unknown, fallback: string): string {
  if (error instanceof HttpErrorResponse) {
    const body = error.error as ApiErrorBody | null;
    if (body?.message) return body.message;
    if (error.status === 0) return 'The Events API is unavailable. Check that the backend is running.';
    return `${fallback} (HTTP ${error.status}).`;
  }
  return fallback;
}

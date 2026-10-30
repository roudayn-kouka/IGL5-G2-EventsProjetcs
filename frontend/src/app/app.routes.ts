import { Routes } from '@angular/router';
import { Logistics } from './pages/logistics/logistics';
import { Stats } from './pages/stats/stats';

export const routes: Routes = [
  { path: '', redirectTo: 'logistics', pathMatch: 'full' },
  { path: 'logistics', component: Logistics },
  { path: 'stats', component: Stats },
  { path: '**', redirectTo: 'logistics' }
];

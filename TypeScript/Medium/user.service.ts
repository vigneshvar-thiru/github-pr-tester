import { Injectable } from '@angular/core';
import { HttpClient, HttpHeaders, HttpParams, HttpErrorResponse } from '@angular/common/http';
import { Observable, throwError, BehaviorSubject } from 'rxjs';
import { catchError, map, tap, retry } from 'rxjs/operators';
import { User, UserProfile, UserRole } from '../Small/user.model';

// Updated: Added session management
@Injectable({
  providedIn: 'root'
})
export class UserService {
  private apiUrl = '/api/users';
  private currentUserSubject = new BehaviorSubject<User | null>(null);
  public currentUser$ = this.currentUserSubject.asObservable();

  private httpOptions = {
    headers: new HttpHeaders({
      'Content-Type': 'application/json'
    })
  };

  constructor(private http: HttpClient) {
    this.loadCurrentUser();
  }

  private loadCurrentUser(): void {
    const storedUser = localStorage.getItem('currentUser');
    if (storedUser) {
      this.currentUserSubject.next(JSON.parse(storedUser));
    }
  }

  getAllUsers(page: number = 0, size: number = 10, role?: UserRole): Observable<{ users: User[], total: number }> {
    let params = new HttpParams()
      .set('page', page.toString())
      .set('size', size.toString());

    if (role) {
      params = params.set('role', role);
    }

    return this.http.get<{ users: User[], total: number }>(this.apiUrl, { params })
      .pipe(
        retry(2),
        catchError(this.handleError)
      );
  }

  getUserById(id: string): Observable<User> {
    return this.http.get<User>(`${this.apiUrl}/${id}`)
      .pipe(
        retry(2),
        catchError(this.handleError)
      );
  }

  createUser(user: Partial<User>): Observable<User> {
    return this.http.post<User>(this.apiUrl, user, this.httpOptions)
      .pipe(
        tap(newUser => console.log(`Created user: ${newUser.email}`)),
        catchError(this.handleError)
      );
  }

  updateUser(id: string, user: Partial<User>): Observable<User> {
    return this.http.put<User>(`${this.apiUrl}/${id}`, user, this.httpOptions)
      .pipe(
        tap(updatedUser => {
          if (this.currentUserSubject.value?.id === id) {
            this.currentUserSubject.next(updatedUser);
            localStorage.setItem('currentUser', JSON.stringify(updatedUser));
          }
        }),
        catchError(this.handleError)
      );
  }

  deleteUser(id: string): Observable<void> {
    return this.http.delete<void>(`${this.apiUrl}/${id}`)
      .pipe(
        tap(() => console.log(`Deleted user: ${id}`)),
        catchError(this.handleError)
      );
  }

  getUserProfile(userId: string): Observable<UserProfile> {
    return this.http.get<UserProfile>(`${this.apiUrl}/${userId}/profile`)
      .pipe(
        retry(2),
        catchError(this.handleError)
      );
  }

  updateUserProfile(userId: string, profile: Partial<UserProfile>): Observable<UserProfile> {
    return this.http.put<UserProfile>(`${this.apiUrl}/${userId}/profile`, profile, this.httpOptions)
      .pipe(
        catchError(this.handleError)
      );
  }

  searchUsers(query: string): Observable<User[]> {
    const params = new HttpParams().set('q', query);
    return this.http.get<User[]>(`${this.apiUrl}/search`, { params })
      .pipe(
        catchError(this.handleError)
      );
  }

  activateUser(id: string): Observable<User> {
    return this.http.patch<User>(`${this.apiUrl}/${id}/activate`, {}, this.httpOptions)
      .pipe(
        catchError(this.handleError)
      );
  }

  deactivateUser(id: string): Observable<User> {
    return this.http.patch<User>(`${this.apiUrl}/${id}/deactivate`, {}, this.httpOptions)
      .pipe(
        catchError(this.handleError)
      );
  }

  changeUserRole(id: string, role: UserRole): Observable<User> {
    return this.http.patch<User>(`${this.apiUrl}/${id}/role`, { role }, this.httpOptions)
      .pipe(
        catchError(this.handleError)
      );
  }

  private handleError(error: HttpErrorResponse): Observable<never> {
    let errorMessage = 'An unknown error occurred';
    
    if (error.error instanceof ErrorEvent) {
      errorMessage = `Client Error: ${error.error.message}`;
    } else {
      errorMessage = `Server Error Code: ${error.status}\nMessage: ${error.message}`;
    }
    
    console.error(errorMessage);
    return throwError(() => new Error(errorMessage));
  }
}

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace SampleApp.Business
{
    /// <summary>
    /// Advanced user authentication and authorization system
    /// Updated: Added OAuth support, enhanced security, and comprehensive session management
    /// </summary>
    /// <remarks>
    /// This system provides comprehensive functionality for:
    /// - User registration and login
    /// - Password hashing and validation
    /// - Role-based access control with permissions
    /// - Session management with refresh tokens
    /// - Password reset and recovery
    /// - Two-factor authentication
    /// - OAuth/SSO provider integration
    /// - Device fingerprinting and IP tracking
    /// - Rate limiting and account lockout
    /// - Comprehensive audit logging
    /// - User profile management
    /// </remarks>
    public class UserAuthenticationSystem
    {
        private readonly Dictionary<int, User> _users;
        private readonly Dictionary<string, Session> _sessions;
        private readonly Dictionary<int, List<AuditLog>> _auditLogs;
        private readonly Dictionary<string, int> _loginAttempts; // IP -> attempt count
        private readonly Dictionary<int, List<ExternalLogin>> _externalLogins;
        private readonly Dictionary<string, RefreshToken> _refreshTokens;
        private readonly IPasswordHasher _passwordHasher;
        private readonly IEmailService _emailService;
        private readonly ITwoFactorAuthService _twoFactorAuthService;
        private readonly IOAuthProviderService _oauthProviderService;
        private int _nextUserId;
        private const int MaxLoginAttemptsPerIp = 10;
        private const int LoginAttemptWindowMinutes = 15;

        public UserAuthenticationSystem(
            IPasswordHasher passwordHasher,
            IEmailService emailService,
            ITwoFactorAuthService twoFactorAuthService,
            IOAuthProviderService oauthProviderService)
        {
            _users = new Dictionary<int, User>();
            _sessions = new Dictionary<string, Session>();
            _auditLogs = new Dictionary<int, List<AuditLog>>();
            _loginAttempts = new Dictionary<string, int>();
            _externalLogins = new Dictionary<int, List<ExternalLogin>>();
            _refreshTokens = new Dictionary<string, RefreshToken>();
            _passwordHasher = passwordHasher ?? throw new ArgumentNullException(nameof(passwordHasher));
            _emailService = emailService ?? throw new ArgumentNullException(nameof(emailService));
            _twoFactorAuthService = twoFactorAuthService ?? throw new ArgumentNullException(nameof(twoFactorAuthService));
            _oauthProviderService = oauthProviderService ?? throw new ArgumentNullException(nameof(oauthProviderService));
            _nextUserId = 1;
        }

        /// <summary>
        /// Registers a new user with validation
        /// </summary>
        public async Task<RegistrationResult> RegisterUserAsync(string username, string email, string password)
        {
            // Validate username
            if (string.IsNullOrWhiteSpace(username) || username.Length < 3)
            {
                return new RegistrationResult { Success = false, ErrorMessage = "Username must be at least 3 characters" };
            }

            // Check if username exists
            if (_users.Values.Any(u => u.Username.Equals(username, StringComparison.OrdinalIgnoreCase)))
            {
                return new RegistrationResult { Success = false, ErrorMessage = "Username already exists" };
            }

            // Validate email
            if (!IsValidEmail(email))
            {
                return new RegistrationResult { Success = false, ErrorMessage = "Invalid email format" };
            }

            // Check if email exists
            if (_users.Values.Any(u => u.Email.Equals(email, StringComparison.OrdinalIgnoreCase)))
            {
                return new RegistrationResult { Success = false, ErrorMessage = "Email already registered" };
            }

            // Validate password strength
            var passwordValidation = ValidatePasswordStrength(password);
            if (!passwordValidation.IsValid)
            {
                return new RegistrationResult { Success = false, ErrorMessage = passwordValidation.ErrorMessage };
            }

            // Create user
            var user = new User
            {
                Id = _nextUserId++,
                Username = username,
                Email = email,
                PasswordHash = _passwordHasher.HashPassword(password),
                CreatedDate = DateTime.UtcNow,
                IsActive = true,
                EmailVerified = false,
                Role = UserRole.User
            };

            _users.Add(user.Id, user);
            _auditLogs[user.Id] = new List<AuditLog>();

            // Send verification email
            await _emailService.SendVerificationEmailAsync(email, GenerateVerificationToken(user.Id));

            LogAuditEvent(user.Id, "UserRegistered", $"User {username} registered successfully");

            return new RegistrationResult { Success = true, UserId = user.Id };
        }

        /// <summary>
        /// Authenticates a user and creates a session
        /// </summary>
        public async Task<LoginResult> LoginAsync(string username, string password, bool rememberMe = false, string ipAddress = null, string deviceFingerprint = null)
        {
            // Check rate limiting
            if (!string.IsNullOrEmpty(ipAddress) && IsRateLimited(ipAddress))
            {
                LogAuditEvent(0, "LoginRateLimited", $"Login rate limit exceeded for IP: {ipAddress}", ipAddress);
                return new LoginResult { Success = false, ErrorMessage = "Too many login attempts. Please try again later." };
            }

            var user = _users.Values.FirstOrDefault(u => u.Username.Equals(username, StringComparison.OrdinalIgnoreCase));

            if (user == null)
            {
                RecordLoginAttempt(ipAddress);
                LogAuditEvent(0, "LoginFailed", $"Login attempt with invalid username: {username}", ipAddress);
                return new LoginResult { Success = false, ErrorMessage = "Invalid username or password" };
            }

            // Check account lockout
            if (user.LockoutEnd.HasValue && user.LockoutEnd.Value > DateTime.UtcNow)
            {
                var remainingTime = (user.LockoutEnd.Value - DateTime.UtcNow).TotalMinutes;
                LogAuditEvent(user.Id, "LoginFailed", $"Login attempt for locked account. Remaining: {remainingTime:F0} minutes", ipAddress);
                return new LoginResult { Success = false, ErrorMessage = $"Account is locked. Try again in {remainingTime:F0} minutes." };
            }

            if (!user.IsActive)
            {
                LogAuditEvent(user.Id, "LoginFailed", "Login attempt for inactive account", ipAddress);
                return new LoginResult { Success = false, ErrorMessage = "Account is disabled" };
            }

            // Verify password
            if (!_passwordHasher.VerifyPassword(password, user.PasswordHash))
            {
                user.FailedLoginAttempts++;
                user.LastFailedLoginDate = DateTime.UtcNow;
                RecordLoginAttempt(ipAddress);

                // Lock account after 5 failed attempts with progressive lockout
                if (user.FailedLoginAttempts >= 5)
                {
                    var lockoutMinutes = Math.Min(user.FailedLoginAttempts * 5, 60); // Max 60 minutes
                    user.LockoutEnd = DateTime.UtcNow.AddMinutes(lockoutMinutes);
                    await _emailService.SendAccountLockedEmailAsync(user.Email);
                    LogAuditEvent(user.Id, "AccountLocked", $"Account locked for {lockoutMinutes} minutes due to {user.FailedLoginAttempts} failed attempts", ipAddress);
                }

                LogAuditEvent(user.Id, "LoginFailed", "Invalid password", ipAddress);
                return new LoginResult { Success = false, ErrorMessage = "Invalid username or password" };
            }

            // Check if 2FA is enabled
            if (user.TwoFactorEnabled)
            {
                return new LoginResult
                {
                    Success = false,
                    RequiresTwoFactor = true,
                    TempUserId = user.Id,
                    ErrorMessage = "Two-factor authentication required"
                };
            }

            return await CreateSessionAsync(user, rememberMe, ipAddress, deviceFingerprint);
        }

        /// <summary>
        /// Verifies two-factor authentication code
        /// </summary>
        public async Task<LoginResult> VerifyTwoFactorAsync(int userId, string code)
        {
            if (!_users.TryGetValue(userId, out var user))
            {
                return new LoginResult { Success = false, ErrorMessage = "User not found" };
            }

            if (!await _twoFactorAuthService.VerifyCodeAsync(user.TwoFactorSecret, code))
            {
                LogAuditEvent(userId, "TwoFactorFailed", "Invalid 2FA code");
                return new LoginResult { Success = false, ErrorMessage = "Invalid verification code" };
            }

            return await CreateSessionAsync(user, false);
        }

        /// <summary>
        /// Creates a session for authenticated user with refresh token support
        /// </summary>
        private async Task<LoginResult> CreateSessionAsync(User user, bool rememberMe, string ipAddress = null, string deviceFingerprint = null)
        {
            var sessionId = Guid.NewGuid().ToString();
            var refreshTokenValue = Guid.NewGuid().ToString();
            
            var session = new Session
            {
                SessionId = sessionId,
                UserId = user.Id,
                CreatedDate = DateTime.UtcNow,
                ExpiresDate = rememberMe ? DateTime.UtcNow.AddDays(30) : DateTime.UtcNow.AddHours(2),
                IsActive = true,
                IpAddress = ipAddress,
                DeviceFingerprint = deviceFingerprint,
                LastActivityDate = DateTime.UtcNow
            };

            _sessions.Add(sessionId, session);

            // Create refresh token for long-lived sessions
            var refreshToken = new RefreshToken
            {
                Token = refreshTokenValue,
                UserId = user.Id,
                SessionId = sessionId,
                CreatedDate = DateTime.UtcNow,
                ExpiresDate = DateTime.UtcNow.AddDays(90),
                IsActive = true
            };
            _refreshTokens.Add(refreshTokenValue, refreshToken);

            user.FailedLoginAttempts = 0;
            user.LockoutEnd = null;
            user.LastLoginDate = DateTime.UtcNow;
            user.LastLoginIp = ipAddress;

            LogAuditEvent(user.Id, "LoginSuccess", $"User logged in successfully from {ipAddress ?? "unknown"}", ipAddress);

            return new LoginResult
            {
                Success = true,
                SessionId = sessionId,
                RefreshToken = refreshTokenValue,
                User = user
            };
        }

        /// <summary>
        /// Validates a session token
        /// </summary>
        public SessionValidationResult ValidateSession(string sessionId)
        {
            if (!_sessions.TryGetValue(sessionId, out var session))
            {
                return new SessionValidationResult { IsValid = false, ErrorMessage = "Invalid session" };
            }

            if (!session.IsActive)
            {
                return new SessionValidationResult { IsValid = false, ErrorMessage = "Session is inactive" };
            }

            if (session.ExpiresDate < DateTime.UtcNow)
            {
                session.IsActive = false;
                return new SessionValidationResult { IsValid = false, ErrorMessage = "Session has expired" };
            }

            if (!_users.TryGetValue(session.UserId, out var user))
            {
                return new SessionValidationResult { IsValid = false, ErrorMessage = "User not found" };
            }

            return new SessionValidationResult
            {
                IsValid = true,
                User = user,
                Session = session
            };
        }

        /// <summary>
        /// Logs out a user by invalidating their session
        /// </summary>
        public bool Logout(string sessionId)
        {
            if (_sessions.TryGetValue(sessionId, out var session))
            {
                session.IsActive = false;
                LogAuditEvent(session.UserId, "Logout", "User logged out");
                return true;
            }
            return false;
        }

        /// <summary>
        /// Changes a user's password
        /// </summary>
        public async Task<bool> ChangePasswordAsync(int userId, string currentPassword, string newPassword)
        {
            if (!_users.TryGetValue(userId, out var user))
                return false;

            if (!_passwordHasher.VerifyPassword(currentPassword, user.PasswordHash))
            {
                LogAuditEvent(userId, "PasswordChangeFailed", "Invalid current password");
                return false;
            }

            var validation = ValidatePasswordStrength(newPassword);
            if (!validation.IsValid)
            {
                return false;
            }

            user.PasswordHash = _passwordHasher.HashPassword(newPassword);
            user.LastPasswordChangeDate = DateTime.UtcNow;

            LogAuditEvent(userId, "PasswordChanged", "Password changed successfully");
            await _emailService.SendPasswordChangedEmailAsync(user.Email);

            return true;
        }

        /// <summary>
        /// Initiates password reset process
        /// </summary>
        public async Task<bool> InitiatePasswordResetAsync(string email)
        {
            var user = _users.Values.FirstOrDefault(u => u.Email.Equals(email, StringComparison.OrdinalIgnoreCase));
            
            if (user == null)
                return false;

            var resetToken = Guid.NewGuid().ToString();
            user.PasswordResetToken = resetToken;
            user.PasswordResetTokenExpiry = DateTime.UtcNow.AddHours(1);

            await _emailService.SendPasswordResetEmailAsync(email, resetToken);
            LogAuditEvent(user.Id, "PasswordResetRequested", "Password reset requested");

            return true;
        }

        /// <summary>
        /// Resets password using reset token
        /// </summary>
        public async Task<bool> ResetPasswordAsync(string resetToken, string newPassword)
        {
            var user = _users.Values.FirstOrDefault(u => u.PasswordResetToken == resetToken);

            if (user == null || user.PasswordResetTokenExpiry < DateTime.UtcNow)
            {
                return false;
            }

            var validation = ValidatePasswordStrength(newPassword);
            if (!validation.IsValid)
            {
                return false;
            }

            user.PasswordHash = _passwordHasher.HashPassword(newPassword);
            user.PasswordResetToken = null;
            user.PasswordResetTokenExpiry = null;
            user.LastPasswordChangeDate = DateTime.UtcNow;

            LogAuditEvent(user.Id, "PasswordReset", "Password reset successfully");
            await _emailService.SendPasswordChangedEmailAsync(user.Email);

            return true;
        }

        /// <summary>
        /// Enables two-factor authentication for a user
        /// </summary>
        public async Task<TwoFactorSetupResult> EnableTwoFactorAsync(int userId)
        {
            if (!_users.TryGetValue(userId, out var user))
            {
                return new TwoFactorSetupResult { Success = false, ErrorMessage = "User not found" };
            }

            var secret = await _twoFactorAuthService.GenerateSecretAsync();
            user.TwoFactorSecret = secret;
            user.TwoFactorEnabled = false; // Will be enabled after verification

            var qrCode = await _twoFactorAuthService.GenerateQrCodeAsync(user.Email, secret);

            LogAuditEvent(userId, "TwoFactorSetupInitiated", "Two-factor authentication setup initiated");

            return new TwoFactorSetupResult
            {
                Success = true,
                Secret = secret,
                QrCodeUrl = qrCode
            };
        }

        /// <summary>
        /// Validates password strength
        /// </summary>
        private PasswordValidationResult ValidatePasswordStrength(string password)
        {
            if (string.IsNullOrWhiteSpace(password) || password.Length < 8)
            {
                return new PasswordValidationResult { IsValid = false, ErrorMessage = "Password must be at least 8 characters" };
            }

            if (!password.Any(char.IsUpper))
            {
                return new PasswordValidationResult { IsValid = false, ErrorMessage = "Password must contain at least one uppercase letter" };
            }

            if (!password.Any(char.IsLower))
            {
                return new PasswordValidationResult { IsValid = false, ErrorMessage = "Password must contain at least one lowercase letter" };
            }

            if (!password.Any(char.IsDigit))
            {
                return new PasswordValidationResult { IsValid = false, ErrorMessage = "Password must contain at least one number" };
            }

            return new PasswordValidationResult { IsValid = true };
        }

        /// <summary>
        /// Validates email format
        /// </summary>
        private bool IsValidEmail(string email)
        {
            if (string.IsNullOrWhiteSpace(email))
                return false;

            var emailPattern = @"^[^@\s]+@[^@\s]+\.[^@\s]+$";
            return Regex.IsMatch(email, emailPattern);
        }

        /// <summary>
        /// Generates verification token
        /// </summary>
        private string GenerateVerificationToken(int userId)
        {
            return Convert.ToBase64String(Encoding.UTF8.GetBytes($"{userId}:{Guid.NewGuid()}"));
        }

        /// <summary>
        /// Logs audit events with IP address tracking
        /// </summary>
        private void LogAuditEvent(int userId, string eventType, string description, string ipAddress = null)
        {
            if (!_auditLogs.ContainsKey(userId))
            {
                _auditLogs[userId] = new List<AuditLog>();
            }

            _auditLogs[userId].Add(new AuditLog
            {
                EventType = eventType,
                Description = description,
                Timestamp = DateTime.UtcNow,
                IpAddress = ipAddress
            });
        }

        /// <summary>
        /// Checks if IP address has exceeded rate limit
        /// </summary>
        private bool IsRateLimited(string ipAddress)
        {
            if (string.IsNullOrEmpty(ipAddress))
                return false;

            CleanupOldLoginAttempts();

            return _loginAttempts.TryGetValue(ipAddress, out var attempts) && attempts >= MaxLoginAttemptsPerIp;
        }

        /// <summary>
        /// Records a failed login attempt from IP
        /// </summary>
        private void RecordLoginAttempt(string ipAddress)
        {
            if (string.IsNullOrEmpty(ipAddress))
                return;

            if (!_loginAttempts.ContainsKey(ipAddress))
                _loginAttempts[ipAddress] = 0;

            _loginAttempts[ipAddress]++;
        }

        /// <summary>
        /// Cleanup old login attempts outside the window
        /// </summary>
        private void CleanupOldLoginAttempts()
        {
            // In production, this would be time-based. Simplified for demo.
            var keysToRemove = _loginAttempts.Where(kvp => kvp.Value > 100).Select(kvp => kvp.Key).ToList();
            foreach (var key in keysToRemove)
                _loginAttempts.Remove(key);
        }

        /// <summary>
        /// Refreshes an access token using a refresh token
        /// </summary>
        public async Task<LoginResult> RefreshTokenAsync(string refreshTokenValue)
        {
            if (!_refreshTokens.TryGetValue(refreshTokenValue, out var refreshToken))
            {
                return new LoginResult { Success = false, ErrorMessage = "Invalid refresh token" };
            }

            if (!refreshToken.IsActive || refreshToken.ExpiresDate < DateTime.UtcNow)
            {
                return new LoginResult { Success = false, ErrorMessage = "Refresh token expired" };
            }

            if (!_users.TryGetValue(refreshToken.UserId, out var user))
            {
                return new LoginResult { Success = false, ErrorMessage = "User not found" };
            }

            // Create new session
            var newSessionId = Guid.NewGuid().ToString();
            var session = new Session
            {
                SessionId = newSessionId,
                UserId = user.Id,
                CreatedDate = DateTime.UtcNow,
                ExpiresDate = DateTime.UtcNow.AddHours(2),
                IsActive = true,
                LastActivityDate = DateTime.UtcNow
            };

            _sessions.Add(newSessionId, session);
            refreshToken.LastUsedDate = DateTime.UtcNow;

            LogAuditEvent(user.Id, "TokenRefreshed", "Access token refreshed");

            return new LoginResult
            {
                Success = true,
                SessionId = newSessionId,
                RefreshToken = refreshTokenValue,
                User = user
            };
        }

        /// <summary>
        /// Links an external OAuth provider to user account
        /// </summary>
        public async Task<bool> LinkExternalProviderAsync(int userId, OAuthProvider provider, string providerUserId, string accessToken)
        {
            if (!_users.ContainsKey(userId))
                return false;

            if (!_externalLogins.ContainsKey(userId))
                _externalLogins[userId] = new List<ExternalLogin>();

            // Check if already linked
            if (_externalLogins[userId].Any(e => e.Provider == provider && e.ProviderUserId == providerUserId))
            {
                return false;
            }

            var externalLogin = new ExternalLogin
            {
                Provider = provider,
                ProviderUserId = providerUserId,
                AccessToken = accessToken,
                LinkedDate = DateTime.UtcNow
            };

            _externalLogins[userId].Add(externalLogin);
            LogAuditEvent(userId, "ExternalProviderLinked", $"Linked {provider} account");

            return true;
        }

        /// <summary>
        /// Authenticates user via external OAuth provider
        /// </summary>
        public async Task<LoginResult> LoginWithExternalProviderAsync(OAuthProvider provider, string providerUserId, string accessToken, string ipAddress = null)
        {
            // Verify token with provider
            var isValid = await _oauthProviderService.ValidateTokenAsync(provider, accessToken);
            if (!isValid)
            {
                LogAuditEvent(0, "ExternalLoginFailed", $"Invalid {provider} token", ipAddress);
                return new LoginResult { Success = false, ErrorMessage = "Invalid provider credentials" };
            }

            // Find user by external login
            var userEntry = _externalLogins.FirstOrDefault(kvp => 
                kvp.Value.Any(e => e.Provider == provider && e.ProviderUserId == providerUserId));

            if (userEntry.Key == 0)
            {
                LogAuditEvent(0, "ExternalLoginFailed", $"No account linked to {provider} user {providerUserId}", ipAddress);
                return new LoginResult { Success = false, ErrorMessage = "No account linked to this provider" };
            }

            var user = _users[userEntry.Key];

            if (!user.IsActive)
            {
                LogAuditEvent(user.Id, "ExternalLoginFailed", "Account is inactive", ipAddress);
                return new LoginResult { Success = false, ErrorMessage = "Account is disabled" };
            }

            return await CreateSessionAsync(user, true, ipAddress, null);
        }

        /// <summary>
        /// Updates user profile information
        /// </summary>
        public async Task<bool> UpdateProfileAsync(int userId, string firstName, string lastName, string phoneNumber)
        {
            if (!_users.TryGetValue(userId, out var user))
                return false;

            user.FirstName = firstName;
            user.LastName = lastName;
            user.PhoneNumber = phoneNumber;

            LogAuditEvent(userId, "ProfileUpdated", "User profile information updated");

            return true;
        }

        /// <summary>
        /// Initiates email change process with verification
        /// </summary>
        public async Task<bool> InitiateEmailChangeAsync(int userId, string newEmail)
        {
            if (!_users.TryGetValue(userId, out var user))
                return false;

            if (!IsValidEmail(newEmail))
                return false;

            // Check if email already exists
            if (_users.Values.Any(u => u.Email.Equals(newEmail, StringComparison.OrdinalIgnoreCase) && u.Id != userId))
                return false;

            var verificationToken = Guid.NewGuid().ToString();
            user.PendingEmail = newEmail;
            user.EmailChangeToken = verificationToken;
            user.EmailChangeTokenExpiry = DateTime.UtcNow.AddHours(24);

            await _emailService.SendVerificationEmailAsync(newEmail, verificationToken);
            LogAuditEvent(userId, "EmailChangeRequested", $"Email change requested to {newEmail}");

            return true;
        }

        /// <summary>
        /// Confirms email change with verification token
        /// </summary>
        public bool ConfirmEmailChange(string verificationToken)
        {
            var user = _users.Values.FirstOrDefault(u => u.EmailChangeToken == verificationToken);

            if (user == null || user.EmailChangeTokenExpiry < DateTime.UtcNow)
                return false;

            user.Email = user.PendingEmail;
            user.PendingEmail = null;
            user.EmailChangeToken = null;
            user.EmailChangeTokenExpiry = null;
            user.EmailVerified = true;

            LogAuditEvent(user.Id, "EmailChanged", $"Email successfully changed to {user.Email}");

            return true;
        }

        /// <summary>
        /// Checks if user has specific permission
        /// </summary>
        public bool HasPermission(int userId, string permission)
        {
            if (!_users.TryGetValue(userId, out var user))
                return false;

            // Admin has all permissions
            if (user.Role == UserRole.Administrator)
                return true;

            return user.Permissions != null && user.Permissions.Contains(permission);
        }

        /// <summary>
        /// Assigns a permission to user
        /// </summary>
        public bool AssignPermission(int userId, string permission)
        {
            if (!_users.TryGetValue(userId, out var user))
                return false;

            if (user.Permissions == null)
                user.Permissions = new List<string>();

            if (!user.Permissions.Contains(permission))
            {
                user.Permissions.Add(permission);
                LogAuditEvent(userId, "PermissionGranted", $"Permission '{permission}' granted");
                return true;
            }

            return false;
        }

        /// <summary>
        /// Revokes a permission from user
        /// </summary>
        public bool RevokePermission(int userId, string permission)
        {
            if (!_users.TryGetValue(userId, out var user))
                return false;

            if (user.Permissions != null && user.Permissions.Remove(permission))
            {
                LogAuditEvent(userId, "PermissionRevoked", $"Permission '{permission}' revoked");
                return true;
            }

            return false;
        }

        /// <summary>
        /// Updates user's role
        /// </summary>
        public bool UpdateUserRole(int userId, UserRole newRole)
        {
            if (!_users.TryGetValue(userId, out var user))
                return false;

            var oldRole = user.Role;
            user.Role = newRole;

            LogAuditEvent(userId, "RoleChanged", $"Role changed from {oldRole} to {newRole}");

            return true;
        }

        /// <summary>
        /// Gets all active sessions for a user
        /// </summary>
        public IEnumerable<Session> GetUserSessions(int userId)
        {
            return _sessions.Values
                .Where(s => s.UserId == userId && s.IsActive && s.ExpiresDate > DateTime.UtcNow)
                .OrderByDescending(s => s.LastActivityDate);
        }

        /// <summary>
        /// Terminates all sessions for a user except current
        /// </summary>
        public int TerminateOtherSessions(int userId, string currentSessionId)
        {
            var sessionsToTerminate = _sessions.Values
                .Where(s => s.UserId == userId && s.SessionId != currentSessionId && s.IsActive)
                .ToList();

            foreach (var session in sessionsToTerminate)
            {
                session.IsActive = false;
            }

            if (sessionsToTerminate.Any())
            {
                LogAuditEvent(userId, "SessionsTerminated", $"Terminated {sessionsToTerminate.Count} other sessions");
            }

            return sessionsToTerminate.Count;
        }

        /// <summary>
        /// Updates session activity timestamp
        /// </summary>
        public bool UpdateSessionActivity(string sessionId)
        {
            if (_sessions.TryGetValue(sessionId, out var session))
            {
                session.LastActivityDate = DateTime.UtcNow;
                return true;
            }
            return false;
        }

        /// <summary>
        /// Gets audit logs for a user
        /// </summary>
        public IEnumerable<AuditLog> GetAuditLogs(int userId, DateTime? startDate = null, DateTime? endDate = null)
        {
            if (!_auditLogs.TryGetValue(userId, out var logs))
                return Enumerable.Empty<AuditLog>();

            var query = logs.AsEnumerable();

            if (startDate.HasValue)
                query = query.Where(l => l.Timestamp >= startDate.Value);

            if (endDate.HasValue)
                query = query.Where(l => l.Timestamp <= endDate.Value);

            return query.OrderByDescending(l => l.Timestamp);
        }
    }

    #region Supporting Classes

    public class User
    {
        public int Id { get; set; }
        public string Username { get; set; }
        public string Email { get; set; }
        public string PasswordHash { get; set; }
        public string FirstName { get; set; }
        public string LastName { get; set; }
        public string PhoneNumber { get; set; }
        public DateTime CreatedDate { get; set; }
        public DateTime? LastLoginDate { get; set; }
        public DateTime? LastFailedLoginDate { get; set; }
        public int FailedLoginAttempts { get; set; }
        public bool IsActive { get; set; }
        public bool EmailVerified { get; set; }
        public UserRole Role { get; set; }
        public List<string> Permissions { get; set; }
        public bool TwoFactorEnabled { get; set; }
        public string TwoFactorSecret { get; set; }
        public string PasswordResetToken { get; set; }
        public DateTime? PasswordResetTokenExpiry { get; set; }
        public DateTime? LastPasswordChangeDate { get; set; }
        public DateTime? LockoutEnd { get; set; }
        public string LastLoginIp { get; set; }
        public string PendingEmail { get; set; }
        public string EmailChangeToken { get; set; }
        public DateTime? EmailChangeTokenExpiry { get; set; }
    }

    public class Session
    {
        public string SessionId { get; set; }
        public int UserId { get; set; }
        public DateTime CreatedDate { get; set; }
        public DateTime ExpiresDate { get; set; }
        public bool IsActive { get; set; }
        public string IpAddress { get; set; }
        public string DeviceFingerprint { get; set; }
        public DateTime? LastActivityDate { get; set; }
    }

    public class AuditLog
    {
        public string EventType { get; set; }
        public string Description { get; set; }
        public DateTime Timestamp { get; set; }
        public string IpAddress { get; set; }
    }

    public enum UserRole
    {
        User,
        Moderator,
        Administrator
    }

    public class RegistrationResult
    {
        public bool Success { get; set; }
        public int UserId { get; set; }
        public string ErrorMessage { get; set; }
    }

    public class LoginResult
    {
        public bool Success { get; set; }
        public string SessionId { get; set; }
        public string RefreshToken { get; set; }
        public User User { get; set; }
        public bool RequiresTwoFactor { get; set; }
        public int TempUserId { get; set; }
        public string ErrorMessage { get; set; }
    }

    public class SessionValidationResult
    {
        public bool IsValid { get; set; }
        public User User { get; set; }
        public Session Session { get; set; }
        public string ErrorMessage { get; set; }
    }

    public class PasswordValidationResult
    {
        public bool IsValid { get; set; }
        public string ErrorMessage { get; set; }
    }

    public class TwoFactorSetupResult
    {
        public bool Success { get; set; }
        public string Secret { get; set; }
        public string QrCodeUrl { get; set; }
        public string ErrorMessage { get; set; }
    }

    public class RefreshToken
    {
        public string Token { get; set; }
        public int UserId { get; set; }
        public string SessionId { get; set; }
        public DateTime CreatedDate { get; set; }
        public DateTime ExpiresDate { get; set; }
        public DateTime? LastUsedDate { get; set; }
        public bool IsActive { get; set; }
    }

    public class ExternalLogin
    {
        public OAuthProvider Provider { get; set; }
        public string ProviderUserId { get; set; }
        public string AccessToken { get; set; }
        public DateTime LinkedDate { get; set; }
    }

    public enum OAuthProvider
    {
        Google,
        Facebook,
        Microsoft,
        GitHub,
        Twitter,
        LinkedIn
    }

    #endregion

    #region Interfaces

    public interface IPasswordHasher
    {
        string HashPassword(string password);
        bool VerifyPassword(string password, string hash);
    }

    public interface IEmailService
    {
        Task SendVerificationEmailAsync(string email, string token);
        Task SendPasswordResetEmailAsync(string email, string token);
        Task SendPasswordChangedEmailAsync(string email);
        Task SendAccountLockedEmailAsync(string email);
    }

    public interface ITwoFactorAuthService
    {
        Task<string> GenerateSecretAsync();
        Task<string> GenerateQrCodeAsync(string email, string secret);
        Task<bool> VerifyCodeAsync(string secret, string code);
    }

    public interface IOAuthProviderService
    {
        Task<bool> ValidateTokenAsync(OAuthProvider provider, string accessToken);
        Task<string> GetUserIdFromProviderAsync(OAuthProvider provider, string accessToken);
    }

    #endregion
}

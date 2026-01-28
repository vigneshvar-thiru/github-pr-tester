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
    /// Updated: Added OAuth support
    /// </summary>
    /// <remarks>
    /// This system provides comprehensive functionality for:
    /// - User registration and login
    /// - Password hashing and validation
    /// - Role-based access control
    /// - Session management
    /// - Password reset and recovery
    /// - Two-factor authentication
    /// - Audit logging
    /// </remarks>
    public class UserAuthenticationSystem
    {
        private readonly Dictionary<int, User> _users;
        private readonly Dictionary<string, Session> _sessions;
        private readonly Dictionary<int, List<AuditLog>> _auditLogs;
        private readonly IPasswordHasher _passwordHasher;
        private readonly IEmailService _emailService;
        private readonly ITwoFactorAuthService _twoFactorAuthService;
        private int _nextUserId;

        public UserAuthenticationSystem(
            IPasswordHasher passwordHasher,
            IEmailService emailService,
            ITwoFactorAuthService twoFactorAuthService)
        {
            _users = new Dictionary<int, User>();
            _sessions = new Dictionary<string, Session>();
            _auditLogs = new Dictionary<int, List<AuditLog>>();
            _passwordHasher = passwordHasher ?? throw new ArgumentNullException(nameof(passwordHasher));
            _emailService = emailService ?? throw new ArgumentNullException(nameof(emailService));
            _twoFactorAuthService = twoFactorAuthService ?? throw new ArgumentNullException(nameof(twoFactorAuthService));
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
        public async Task<LoginResult> LoginAsync(string username, string password, bool rememberMe = false)
        {
            var user = _users.Values.FirstOrDefault(u => u.Username.Equals(username, StringComparison.OrdinalIgnoreCase));

            if (user == null)
            {
                LogAuditEvent(0, "LoginFailed", $"Login attempt with invalid username: {username}");
                return new LoginResult { Success = false, ErrorMessage = "Invalid username or password" };
            }

            if (!user.IsActive)
            {
                LogAuditEvent(user.Id, "LoginFailed", "Login attempt for inactive account");
                return new LoginResult { Success = false, ErrorMessage = "Account is disabled" };
            }

            // Verify password
            if (!_passwordHasher.VerifyPassword(password, user.PasswordHash))
            {
                user.FailedLoginAttempts++;
                user.LastFailedLoginDate = DateTime.UtcNow;

                // Lock account after 5 failed attempts
                if (user.FailedLoginAttempts >= 5)
                {
                    user.IsActive = false;
                    await _emailService.SendAccountLockedEmailAsync(user.Email);
                    LogAuditEvent(user.Id, "AccountLocked", "Account locked due to excessive failed login attempts");
                }

                LogAuditEvent(user.Id, "LoginFailed", "Invalid password");
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

            return await CreateSessionAsync(user, rememberMe);
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
        /// Creates a session for authenticated user
        /// </summary>
        private async Task<LoginResult> CreateSessionAsync(User user, bool rememberMe)
        {
            var sessionId = Guid.NewGuid().ToString();
            var session = new Session
            {
                SessionId = sessionId,
                UserId = user.Id,
                CreatedDate = DateTime.UtcNow,
                ExpiresDate = rememberMe ? DateTime.UtcNow.AddDays(30) : DateTime.UtcNow.AddHours(2),
                IsActive = true
            };

            _sessions.Add(sessionId, session);

            user.FailedLoginAttempts = 0;
            user.LastLoginDate = DateTime.UtcNow;

            LogAuditEvent(user.Id, "LoginSuccess", $"User logged in successfully");

            return new LoginResult
            {
                Success = true,
                SessionId = sessionId,
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
        /// Logs audit events
        /// </summary>
        private void LogAuditEvent(int userId, string eventType, string description)
        {
            if (!_auditLogs.ContainsKey(userId))
            {
                _auditLogs[userId] = new List<AuditLog>();
            }

            _auditLogs[userId].Add(new AuditLog
            {
                EventType = eventType,
                Description = description,
                Timestamp = DateTime.UtcNow
            });
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
        public DateTime CreatedDate { get; set; }
        public DateTime? LastLoginDate { get; set; }
        public DateTime? LastFailedLoginDate { get; set; }
        public int FailedLoginAttempts { get; set; }
        public bool IsActive { get; set; }
        public bool EmailVerified { get; set; }
        public UserRole Role { get; set; }
        public bool TwoFactorEnabled { get; set; }
        public string TwoFactorSecret { get; set; }
        public string PasswordResetToken { get; set; }
        public DateTime? PasswordResetTokenExpiry { get; set; }
        public DateTime? LastPasswordChangeDate { get; set; }
    }

    public class Session
    {
        public string SessionId { get; set; }
        public int UserId { get; set; }
        public DateTime CreatedDate { get; set; }
        public DateTime ExpiresDate { get; set; }
        public bool IsActive { get; set; }
    }

    public class AuditLog
    {
        public string EventType { get; set; }
        public string Description { get; set; }
        public DateTime Timestamp { get; set; }
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

    #endregion
}

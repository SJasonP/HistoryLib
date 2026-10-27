using Windows.Security.Credentials.UI;

namespace HistoryLib.Windows.Core;

public sealed class PrivacyLockService
{
    private const string SettingKey = "privacy_lock_enabled";
    private readonly WindowsSettingsStore _settings = new();

    public bool IsEnabled => _settings.GetBool(SettingKey, true);

    public void SetEnabled(bool enabled) => _settings.Set(SettingKey, enabled);

    public async Task<bool> AuthenticateAsync()
    {
        if (!IsEnabled) return true;

        var availability = await UserConsentVerifier.CheckAvailabilityAsync();
        if (availability != UserConsentVerifierAvailability.Available) return false;

        var result = await UserConsentVerifier.RequestVerificationAsync("验证后打开 HistoryLib");
        return result == UserConsentVerificationResult.Verified;
    }
}

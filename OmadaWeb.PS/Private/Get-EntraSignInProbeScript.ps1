function Get-EntraSignInProbeScript {
    <#
    .SYNOPSIS
        Returns the JavaScript that reads one language-independent snapshot off an Entra ID sign-in
        page.

    .DESCRIPTION
        The sign-in automation used to ask the page a question per step - is this element there, is
        it visible, what does that button say - which meant a decision spread over half a dozen
        asynchronous round trips, and one that could only be exercised with a real browser in front
        of it. This returns a single script that reads everything the rules in
        Resolve-EntraSignInScreen need, once, into one JSON document. What comes back is data, so
        the decision made from it is a function that can be tested.

        Nothing it reads is text a person sees. The Entra sign-in app is served in the user's
        language, so any rule written against a visible label works on English tenants and silently
        does nothing everywhere else. The snapshot therefore carries only things the server decides:

          - Which of the ids in $Script:EntraSignInElementId are on the page, and which of those are
            visible, enabled and not hidden from assistive technology.
          - The numbers out of the object the page ships its own state in - '$Config', also served as
            ServerData: 'iErrorCode' and 'sErrorCode', which are the AADSTS codes, and the
            'arrUserProofs' array, whose 'authMethodId' values name the offered verification methods
            in a fixed vocabulary rather than in prose.
          - The 'data-test-id' of each account tile on 'Pick an account' - Entra puts the account
            name there - and whether the tile that leads to another account exists.
          - The approval number, from both the element passwordless sign-in shows it in and the one
            Authenticator number match uses.
          - Whether a password field and an e-mail field are visible at all, by input type. This is
            the only rule that does not depend on an id, and it exists so that a page whose ids
            Microsoft has renamed can still be reported as "this was the password screen" instead of
            as "nothing matched".

        The ids are injected from $Script:EntraSignInElementId rather than written out here, so the
        script and the rules that read its output cannot come to disagree about a selector.

    .OUTPUTS
        System.String. JavaScript returning a JSON document with the members 'ids', 'visibleIds',
        'errorCode', 'errorCodeText', 'proofs', 'proofOptionCount', 'accountTiles', 'hasOtherTile',
        'displaySign', 'hasVisiblePasswordInput', 'hasVisibleEmailInput' and 'path'.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    # The script depends on nothing but the selector table, and the sign-in reads the page again and
    # again while a user works through it - so it is built once and handed out after that. The build
    # is small, but it happens on the WebView2 UI thread, which is the one place in this module where
    # small and repeated is worth not doing at all.
    if (-not [string]::IsNullOrEmpty($Script:EntraSignInProbeScript)) {
        return $Script:EntraSignInProbeScript
    }

    $ElementIdJson = ConvertTo-Json -InputObject @($Script:EntraSignInElementId.Values) -Compress
    $ProofsContainerJson = ConvertTo-JavaScriptLiteral $Script:EntraSignInElementId.ProofsContainer
    $PasswordlessNumberJson = ConvertTo-JavaScriptLiteral $Script:EntraSignInElementId.PasswordlessNumber
    $NumberMatchJson = ConvertTo-JavaScriptLiteral $Script:EntraSignInElementId.NumberMatch

    $ProbeScript = @'
(function () {
    var knownIds = __ELEMENT_IDS__;
    var proofsContainerId = __PROOFS_CONTAINER_ID__;
    var passwordlessNumberId = __PASSWORDLESS_NUMBER_ID__;
    var numberMatchId = __NUMBER_MATCH_ID__;

__IS_VISIBLE__

    function readNumber(element) {
        if (!element) { return null; }
        var value = null;
        if (element.childNodes && element.childNodes[0] && element.childNodes[0].data) {
            value = element.childNodes[0].data;
        }
        if (!value) { value = element.textContent; }
        if (!value) { return null; }
        value = value.replace(/\s+/g, ' ').trim();
        return value.length > 0 ? value : null;
    }

    var ids = [];
    var visibleIds = [];
    for (var i = 0; i < knownIds.length; i++) {
        var element = document.getElementById(knownIds[i]);
        if (!element) { continue; }
        ids.push(knownIds[i]);
        if (isVisible(element)) { visibleIds.push(knownIds[i]); }
    }

    // The sign-in app publishes its own server-side state on the window. Everything read from it is
    // numeric or an identifier - never a rendered sentence.
    var config = null;
    try { config = window.$Config || window.ServerData || null; }
    catch (e) { config = null; }

    var errorCode = '';
    var errorCodeText = '';
    var proofs = [];
    if (config) {
        if (config.iErrorCode !== undefined && config.iErrorCode !== null) { errorCode = String(config.iErrorCode); }
        if (config.sErrorCode !== undefined && config.sErrorCode !== null) { errorCodeText = String(config.sErrorCode); }
        if (config.arrUserProofs && config.arrUserProofs.length) {
            for (var p = 0; p < config.arrUserProofs.length; p++) {
                var proof = config.arrUserProofs[p] || {};
                proofs.push({
                    authMethodId: proof.authMethodId ? String(proof.authMethodId) : '',
                    isDefault: proof.isDefault === true
                });
            }
        }
    }

    // One clickable option per offered method. Counted rather than matched to a method, because the
    // options carry no identifier naming which method they are; Resolve-EntraSignInScreen refuses to
    // click by position when this count and the proofs array disagree.
    //
    // Only the options a user could actually click are counted, which is what makes that check mean
    // anything: a hidden template option counted here but skipped by the click - or the reverse -
    // shifts every index after it, and the click still succeeds, so the account is sent a different
    // verification method than the one that was chosen and nothing reports an error. The click
    // filters through this same isVisible.
    var proofOptionCount = 0;
    var proofsContainer = document.getElementById(proofsContainerId);
    if (proofsContainer) {
        var options = proofsContainer.querySelectorAll('[data-value], [role="button"], [role="listitem"]');
        var counted = [];
        for (var o = 0; o < options.length; o++) {
            if (counted.indexOf(options[o]) === -1 && isVisible(options[o])) { counted.push(options[o]); }
        }
        proofOptionCount = counted.length;
    }

    // Entra writes the account name of each tile on 'Pick an account' into data-test-id.
    var accountTiles = [];
    var tiles = document.querySelectorAll('[data-test-id]');
    for (var t = 0; t < tiles.length; t++) {
        var testId = tiles[t].getAttribute('data-test-id');
        if (!testId) { continue; }
        if (!isVisible(tiles[t])) { continue; }
        accountTiles.push({ index: accountTiles.length, testId: String(testId) });
    }

    var hasOtherTile = document.querySelector('[aria-labelledby="otherTileText"]') !== null || document.getElementById('otherTileText') !== null;

    var displaySign = readNumber(document.getElementById(passwordlessNumberId));
    if (!displaySign) { displaySign = readNumber(document.getElementById(numberMatchId)); }

    // Type-based, so a renamed id still tells the diagnostic which screen this was.
    var hasVisiblePasswordInput = false;
    var passwordInputs = document.querySelectorAll('input[type="password"]');
    for (var w = 0; w < passwordInputs.length; w++) {
        if (isVisible(passwordInputs[w])) { hasVisiblePasswordInput = true; break; }
    }

    var hasVisibleEmailInput = false;
    var emailInputs = document.querySelectorAll('input[type="email"], input[name="loginfmt"]');
    for (var m = 0; m < emailInputs.length; m++) {
        if (isVisible(emailInputs[m])) { hasVisibleEmailInput = true; break; }
    }

    return JSON.stringify({
        ids: ids,
        visibleIds: visibleIds,
        errorCode: errorCode,
        errorCodeText: errorCodeText,
        proofs: proofs,
        proofOptionCount: proofOptionCount,
        accountTiles: accountTiles,
        hasOtherTile: hasOtherTile,
        displaySign: displaySign,
        hasVisiblePasswordInput: hasVisiblePasswordInput,
        hasVisibleEmailInput: hasVisibleEmailInput,
        path: window.location.pathname || ''
    });
})();
'@

    $ProbeScript = $ProbeScript.Replace("__IS_VISIBLE__", (Get-EntraElementVisibilityScript))
    $ProbeScript = $ProbeScript.Replace("__ELEMENT_IDS__", $ElementIdJson)
    $ProbeScript = $ProbeScript.Replace("__PROOFS_CONTAINER_ID__", $ProofsContainerJson)
    $ProbeScript = $ProbeScript.Replace("__PASSWORDLESS_NUMBER_ID__", $PasswordlessNumberJson)
    $ProbeScript = $ProbeScript.Replace("__NUMBER_MATCH_ID__", $NumberMatchJson)

    # Populated before returning, so that the very next call is the cached one.
    $Script:EntraSignInProbeScript = $ProbeScript

    return $ProbeScript
}

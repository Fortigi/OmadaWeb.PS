function Get-OmadaLogonErrorScript {
    <#
    .SYNOPSIS
        Returns the JavaScript that reads an error banner off an Omada logon page.

    .DESCRIPTION
        When a federated sign-in fails, the identity provider hands the browser back to Omada and
        Omada renders the failure on its own logon landing page - not as an HTTP error, and not as a
        redirect the module can recognize by URL. The page simply sits there, no oisauthtoken cookie
        is ever set, and both login drivers keep waiting for one that will never arrive.

        This is the single source of truth for how that banner is found, shared by both drivers so
        WebView2 and Edge WebDriver cannot drift apart on it. The returned script is an immediately
        invoked function expression, which is what CoreWebView2.ExecuteScriptAsync expects; the
        WebDriver call site prefixes "return " because Selenium executes a script as a function body.

        What it looks at, in widening order:

          - The page-message container Omada renders every page-level message into. In the markup it
            is a span with id 'PageMsgsContnr' wrapping a table of class 'InfoTextPageWideTable', but
            an ASP.NET control hierarchy can prefix that id, so a suffix match is included too.
          - Anywhere on the page, but only while the browser is on a logon/sign-in/error path. This
            is the "any error shown on the landing page" case: Omada themes and versions do not agree
            on the markup, so the sweep keys on the severity class instead of on a fixed selector.

        Severity, not position, is what marks a message as an error: Omada writes 'InfoText Error
        GlobPage' on a failure and leaves the 'Error' class off an ordinary notice such as a session
        that timed out. Matching the class as a whole word keeps 'ErrorFree' or 'terror' from
        counting, and role="alert" covers markup that carries the severity in ARIA instead.

        Only the innermost matching element of a nest is reported, so the message is the sentence
        Omada wrote rather than that sentence wrapped in every ancestor's text.

        It also reports whether the page still offers a way to sign in - a visible password box, or a
        visible field that names itself as the user name - and whether this is a sign-in page at all.
        Test-OmadaLogonPageError uses both to tell an error the user can correct in the open window
        from one only a different account or an administrator can resolve.

    .OUTPUTS
        System.String. JavaScript returning a JSON document with the members 'found', 'message',
        'source', 'hasLogonForm', 'onLogonPage' and 'path'.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    return @'
(function () {
    function isVisible(element) {
        if (!element) { return false; }
        try {
            var style = window.getComputedStyle(element);
            if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') { return false; }
        }
        catch (e) { return false; }
        return element.offsetWidth > 0 || element.offsetHeight > 0 || element.getClientRects().length > 0;
    }

    function readText(element) {
        var value = element.innerText || element.textContent || '';
        return value.replace(/\s+/g, ' ').trim();
    }

    function isErrorElement(element) {
        if (!element || element.nodeType !== 1) { return false; }
        var names = element.className;
        if (typeof names !== 'string') { names = element.getAttribute('class') || ''; }
        var tokens = names.split(/\s+/);
        for (var t = 0; t < tokens.length; t++) {
            var token = tokens[t];
            if (!token) { continue; }
            // 'Error', 'page-error' and 'form_error' - the class names a severity.
            if (/(^|[-_])error([-_]|$)/i.test(token)) { return true; }
            // 'ErrorText', 'errorMessage' - the same severity, spelled as one word. Written out
            // rather than matched as a prefix so that 'ErrorFree' does not count as an error.
            if (/^error(text|message|msg|label|summary|banner)$/i.test(token)) { return true; }
        }
        var role = element.getAttribute('role') || '';
        return role.toLowerCase() === 'alert';
    }

    var path = window.location.pathname || '';
    var onLogonPage = /logon|login|signin|sign-in|error/i.test(path);

    var roots = [];
    var containers = document.querySelectorAll('#PageMsgsContnr, [id$="PageMsgsContnr"], .InfoTextPageWideTable');
    for (var c = 0; c < containers.length; c++) { roots.push(containers[c]); }
    if (onLogonPage && document.body) { roots.push(document.body); }

    var candidates = [];
    for (var r = 0; r < roots.length; r++) {
        var root = roots[r];
        if (!root) { continue; }
        if (isErrorElement(root) && candidates.indexOf(root) === -1) { candidates.push(root); }
        var nested = root.querySelectorAll('*');
        for (var n = 0; n < nested.length; n++) {
            if (isErrorElement(nested[n]) && candidates.indexOf(nested[n]) === -1) { candidates.push(nested[n]); }
        }
    }

    var messages = [];
    var sources = [];
    for (var i = 0; i < candidates.length; i++) {
        var candidate = candidates[i];

        var wrapsAnother = false;
        for (var j = 0; j < candidates.length; j++) {
            if (i !== j && candidate.contains(candidates[j])) { wrapsAnother = true; break; }
        }
        if (wrapsAnother) { continue; }
        if (!isVisible(candidate)) { continue; }

        var message = readText(candidate);
        if (!message) { continue; }
        // A banner that dumps a stack trace is still a refusal. Cap it rather than dropping it,
        // so an over-long message never reads as 'no error at all'. The classifier truncates
        // again for display; this cap only keeps the payload out of the megabyte range.
        if (message.length > 4000) { message = message.substring(0, 4000); }
        if (messages.indexOf(message) !== -1) { continue; }

        messages.push(message);
        sources.push(candidate.id || candidate.className || candidate.tagName);
    }

    var hasLogonForm = false;
    var passwords = document.querySelectorAll('input[type="password"]');
    for (var p = 0; p < passwords.length; p++) {
        if (isVisible(passwords[p])) { hasLogonForm = true; break; }
    }
    if (!hasLogonForm) {
        var fields = document.querySelectorAll('input[type="text"], input[type="email"], input:not([type])');
        for (var f = 0; f < fields.length; f++) {
            var field = fields[f];
            var hint = ((field.id || '') + ' ' + (field.name || '') + ' ' + (field.getAttribute('autocomplete') || '')).toLowerCase();
            if (isVisible(field) && /user|logon|login|email|account/.test(hint)) { hasLogonForm = true; break; }
        }
    }

    return JSON.stringify({
        found: messages.length > 0,
        message: messages.join(' '),
        source: sources.join(', '),
        hasLogonForm: hasLogonForm,
        onLogonPage: onLogonPage,
        path: path
    });
})();
'@
}

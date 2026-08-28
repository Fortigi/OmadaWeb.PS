function Get-EntraElementVisibilityScript {
    <#
    .SYNOPSIS
        Returns the JavaScript function the sign-in automation decides "the user can see and act on
        this" with.

    .DESCRIPTION
        Three scripts need this question answered and they must answer it identically: the probe that
        reports what is on the page, the click that picks an account tile, and the click that picks a
        verification method. When they disagree, the disagreement is silent and it is a loop - the
        probe reports an element the click cannot find, or the click acts on an element the probe
        never counted, and either way the page does not change while the driver believes it acted.

        So the definition lives here, once, and is injected into each of them - the same reason the
        element ids live in $Script:EntraSignInElementId rather than in each script that looks for
        them.

        Visible means all of: not display:none, not visibility:hidden, not fully transparent, not
        marked aria-hidden, neither disabled nor read-only, and occupying somewhere on the page.
        getComputedStyle throws on a detached node, which is not a visible element either, so it is
        caught.

        Read-only counts as not visible because of what the answer is used for. Nothing here merely
        looks at an element - it fills it in or clicks it - and a field that cannot be typed into is
        as useless to that as one that cannot be seen.

    .OUTPUTS
        System.String. A JavaScript function declaration named isVisible, to be pasted into a larger
        script.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param()

    return @'
    function isVisible(element) {
        if (!element) { return false; }
        try {
            var style = window.getComputedStyle(element);
            if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') { return false; }
        }
        catch (e) { return false; }
        if (element.getAttribute('aria-hidden') === 'true') { return false; }
        if (element.disabled === true || element.readOnly === true) { return false; }
        return element.offsetWidth > 0 || element.offsetHeight > 0 || element.getClientRects().length > 0;
    }
'@
}

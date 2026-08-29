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
        clipped away to nothing, not marked aria-hidden, neither disabled nor read-only, and big
        enough on the page to be aimed at. getComputedStyle throws on a detached node, which is not a
        visible element either, so it is caught.

        Read-only counts as not visible because of what the answer is used for. Nothing here merely
        looks at an element - it fills it in or clicks it - and a field that cannot be typed into is
        as useless to that as one that cannot be seen.

        The size floor and the clip tests are there for one specific and very common thing: the
        "visually hidden" pattern, which hides an element from sight while leaving it to screen
        readers by shrinking it to a pixel and clipping it away - position:absolute with width:1px,
        height:1px and clip:rect(0 0 0 0), or a clip-path of inset(50%). None of the property checks
        above see anything wrong with such an element: it is displayed, opaque, and reports a
        non-zero width. Asking only whether it occupies *somewhere* therefore called it visible,
        which is how a hidden template option or account tile could be counted and clicked. Nothing
        a user is expected to click is two pixels across, so the floor costs nothing and closes that.

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
        if (style.clip === 'rect(0px, 0px, 0px, 0px)') { return false; }
        if (style.clipPath === 'inset(50%)') { return false; }
        if (element.getAttribute('aria-hidden') === 'true') { return false; }
        if (element.disabled === true || element.readOnly === true) { return false; }
        var rect = element.getBoundingClientRect();
        return rect.width >= 2 && rect.height >= 2;
    }
'@
}

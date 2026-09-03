const targetOutputName = "HDMI-A-1";
const policyKitIdentity = "org.kde.polkit-kde-authentication-agent-1";

function isPolicyKitPrompt(window) {
    return window.resourceClass === policyKitIdentity
        || window.desktopFileName === policyKitIdentity;
}

function targetOutput() {
    return workspace.screens.find(output => output.name === targetOutputName);
}

function placePrompt(window) {
    if (!isPolicyKitPrompt(window)) {
        return;
    }

    const output = targetOutput();
    if (!output) {
        console.warn(
            "aeris-auth-primary: target output " + targetOutputName + " is unavailable"
        );
        return;
    }

    if (window.output !== output) {
        const previousOutput = window.output ? window.output.name : "unknown";
        workspace.sendClientToScreen(window, output);
        console.info(
            "aeris-auth-primary: moved PolicyKit prompt from "
            + previousOutput + " to " + targetOutputName
        );
    } else {
        console.info(
            "aeris-auth-primary: PolicyKit prompt already on " + targetOutputName
        );
    }
}

workspace.windowList().forEach(placePrompt);
workspace.windowAdded.connect(placePrompt);

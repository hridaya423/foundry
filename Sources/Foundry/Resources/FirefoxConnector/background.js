let port = null;

function connect() {
  port = browser.runtime.connectNative("com.hridya.foundry");
  port.onDisconnect.addListener(() => {
    port = null;
    setTimeout(connect, 5000);
  });
  publishTabs();
}

async function publishTabs() {
  if (!port) return;
  const tabs = await browser.tabs.query({});
  port?.postMessage({
    tabs: tabs
      .filter(tab => typeof tab.url === "string" && tab.url.length > 0)
      .map(tab => ({ title: tab.title || "", url: tab.url }))
  });
}

browser.tabs.onCreated.addListener(publishTabs);
browser.tabs.onRemoved.addListener(publishTabs);
browser.tabs.onUpdated.addListener(publishTabs);
browser.tabs.onActivated.addListener(publishTabs);
connect();

const port = browser.runtime.connectNative("com.hridya.foundry");

async function publishTabs() {
  const tabs = await browser.tabs.query({});
  port.postMessage({
    tabs: tabs
      .filter(tab => typeof tab.url === "string" && tab.url.length > 0)
      .map(tab => ({ title: tab.title || "", url: tab.url }))
  });
}

port.onDisconnect.addListener(() => {});
browser.tabs.onCreated.addListener(publishTabs);
browser.tabs.onRemoved.addListener(publishTabs);
browser.tabs.onUpdated.addListener(publishTabs);
browser.tabs.onActivated.addListener(publishTabs);
publishTabs();

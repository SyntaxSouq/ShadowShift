/**
 * ShadowShift - Playwright Integration Example
 * Author: SyntaxSouq
 * Repository: https://github.com/SyntaxSouq
 */

const { chromium } = require('playwright');

(async () => {
  // ShadowShift must be running on port 9050 (default Tor SOCKS port)
  const browser = await chromium.launch({
    proxy: {
      server: 'socks5://127.0.0.1:9050'
    }
  });

  const page = await browser.newPage();
  
  console.log('Fetching current IP via ShadowShift...');
  await page.goto('https://check.torproject.org/api/ip');
  const content = await page.textContent('body');
  const ipData = JSON.parse(content);
  
  console.log(`ShadowShift IP: ${ipData.IP}`);
  
  await browser.close();
})();

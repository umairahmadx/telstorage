/**
 * Google Apps Script for TelStorage Authentication
 * 
 * Setup Instructions:
 * 1. Create a new Google Sheet
 * 2. Rename the first tab to "users"
 * 3. Add header row: email | password | bot_token | channel_id
 * 4. Go to Extensions → Apps Script
 * 5. Paste this code
 * 6. Deploy → New Deployment → Web App
 *    - Execute as: Me
 *    - Who has access: Anyone
 * 7. Copy the Web App URL and paste it in app_constants.dart
 */

const SHEET_NAME = 'users';

function doGet(e) {
  const action = e.parameter.action;

  if (action === 'login') {
    return login(e.parameter.email, e.parameter.password);
  }

  return respond({ success: false, message: 'Unknown action' });
}

function login(email, password) {
  const row = findUser(email);
  
  if (!row) {
    return respond({ success: false, message: 'User not found' });
  }

  if (row.password !== password) {
    return respond({ success: false, message: 'Wrong password' });
  }

  return respond({
    success: true,
    bot_token: String(row.bot_token),
    channel_id: String(row.channel_id)
  });
}

function register(email, password, bot_token, channel_id) {
  if (findUser(email)) {
    return respond({ success: false, message: 'Email already exists' });
  }

  getSheet().appendRow([
    email,
    password,
    bot_token,
    channel_id
  ]);

  return respond({ success: true });
}

function findUser(email) {
  const sheet = getSheet();
  const data = sheet.getDataRange().getValues();
  const headers = data[0];
  const col = name => headers.indexOf(name);

  for (let i = 1; i < data.length; i++) {
    if (data[i][col('email')] === email) {
      return {
        email: String(data[i][col('email')]),
        password: String(data[i][col('password')]),
        bot_token: String(data[i][col('bot_token')]),
        channel_id: String(data[i][col('channel_id')])
      };
    }
  }

  return null;
}

function getSheet() {
  return SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);
}

function respond(data) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}

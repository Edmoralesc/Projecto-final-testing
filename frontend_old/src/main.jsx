import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.jsx';

// Mount the React app into the #root element in index.html
ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);

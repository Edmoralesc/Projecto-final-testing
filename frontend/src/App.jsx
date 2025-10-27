import React, { useState } from 'react';
import './App.css';

function App() {
  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(false);

  const checkStatus = async () => {
    setLoading(true);
    try {
      // Use Vite env variable or fallback to localhost
      const backendUrl = import.meta.env.VITE_API_URL || 'http://localhost:8000';
      const response = await fetch(`${backendUrl}/ping`);
      setStatus(response.ok ? 'ok' : 'error');
    } catch {
      setStatus('error');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="App">
      {status === null ? (
        <div className="welcome-screen">
          <h1>Welcome to FastAPI</h1>
          <button onClick={checkStatus} disabled={loading}>
            {loading ? 'Checking...' : 'Check Status'}
          </button>
        </div>
      ) : (
        <div className={`status-screen ${status === 'ok' ? 'green' : 'red'}`}>
          <h1>
            {status === 'ok' ? 'API Status: Online' : 'API Status: Offline'}
          </h1>
          <p>
            {status === 'ok'
              ? '✓ Connection successful'
              : '✗ Connection failed'}
          </p>
          <button onClick={() => setStatus(null)}>Back</button>
        </div>
      )}
    </div>
  );
}

export default App;

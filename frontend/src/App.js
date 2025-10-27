import React, { useState } from 'react';
import './App.css';

function App() {
  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(false);

  const checkStatus = async () => {
    setLoading(true);
    try {
      // Change this URL to your actual backend URL
      const response = await fetch('http://localhost:8000/ping');
      if (response.status === 200) {
        setStatus('ok');
      } else {
        setStatus('error');
      }
    } catch (error) {
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
          <h1>{status === 'ok' ? 'API Status: Online' : 'API Status: Offline'}</h1>
          <p>{status === 'ok' ? '✓ Connection successful' : '✗ Connection failed'}</p>
          <button onClick={() => setStatus(null)}>Back</button>
        </div>
      )}
    </div>
  );
}

export default App;

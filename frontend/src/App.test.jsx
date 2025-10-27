import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import App from './App';

// Mock fetch with Vitest
beforeEach(() => {
  global.fetch = vi.fn();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('App', () => {
  it('renders the welcome screen initially', () => {
    render(<App />);
    expect(screen.getByText(/welcome to fastapi/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /check status/i })).toBeInTheDocument();
  });

  it('shows "Checking..." while loading', async () => {
    global.fetch.mockResolvedValue({ ok: true });
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: /check status/i }));
    expect(screen.getByText(/checking/i)).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText(/api status/i)).toBeInTheDocument());
  });

  it('shows success status when API response is ok', async () => {
    global.fetch.mockResolvedValue({ ok: true });
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: /check status/i }));
    await waitFor(() =>
      expect(screen.getByText(/api status: online/i)).toBeInTheDocument()
    );
    expect(screen.getByText(/✓ connection successful/i)).toBeInTheDocument();
  });

  it('shows error status if API response is not ok', async () => {
    global.fetch.mockResolvedValue({ ok: false });
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: /check status/i }));
    await waitFor(() =>
      expect(screen.getByText(/api status: offline/i)).toBeInTheDocument()
    );
    expect(screen.getByText(/✗ connection failed/i)).toBeInTheDocument();
  });

  it('allows user to go back to welcome screen', async () => {
    global.fetch.mockResolvedValue({ ok: true });
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: /check status/i }));
    await waitFor(() => screen.getByRole('button', { name: /back/i }));
    fireEvent.click(screen.getByRole('button', { name: /back/i }));
    expect(screen.getByText(/welcome to fastapi/i)).toBeInTheDocument();
  });

  it('shows error status if fetch throws', async () => {
    global.fetch.mockRejectedValue(new Error('Network Error'));
    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: /check status/i }));
    await waitFor(() =>
      expect(screen.getByText(/api status: offline/i)).toBeInTheDocument()
    );
  });
});

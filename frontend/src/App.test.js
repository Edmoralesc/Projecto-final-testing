import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import App from './App';

// Mock fetch globally
global.fetch = jest.fn();

describe('App Component', () => {
  beforeEach(() => {
    // Clear all mocks before each test
    jest.clearAllMocks();
  });

  describe('Initial Render', () => {
    test('renders welcome screen on initial load', () => {
      render(<App />);
      
      expect(screen.getByText('Welcome to FastAPI')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /check status/i })).toBeInTheDocument();
    });

    test('check status button is enabled initially', () => {
      render(<App />);
      
      const button = screen.getByRole('button', { name: /check status/i });
      expect(button).not.toBeDisabled();
    });
  });

  describe('Status Check - Success (200 OK)', () => {
    test('displays green status screen when API returns 200', async () => {
      // Mock successful fetch response
      fetch.mockResolvedValueOnce({
        status: 200,
      });

      render(<App />);
      
      const checkButton = screen.getByRole('button', { name: /check status/i });
      fireEvent.click(checkButton);

      // Wait for status screen to appear
      await waitFor(() => {
        expect(screen.getByText('API Status: Online')).toBeInTheDocument();
      });

      expect(screen.getByText('✓ Connection successful')).toBeInTheDocument();
      
      // Check if green class is applied
      const statusScreen = screen.getByText('API Status: Online').closest('div');
      expect(statusScreen).toHaveClass('green');
    });

    test('button shows "Checking..." text while loading', async () => {
      // Mock fetch with delay
      fetch.mockImplementationOnce(() => 
        new Promise(resolve => setTimeout(() => resolve({ status: 200 }), 100))
      );

      render(<App />);
      
      const checkButton = screen.getByRole('button', { name: /check status/i });
      fireEvent.click(checkButton);

      // Button should show "Checking..." immediately
      expect(screen.getByRole('button', { name: /checking/i })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /checking/i })).toBeDisabled();

      // Wait for completion
      await waitFor(() => {
        expect(screen.getByText('API Status: Online')).toBeInTheDocument();
      });
    });
  });

  describe('Status Check - Failure (Non-200)', () => {
    test('displays red status screen when API returns 404', async () => {
      fetch.mockResolvedValueOnce({
        status: 404,
      });

      render(<App />);
      
      const checkButton = screen.getByRole('button', { name: /check status/i });
      fireEvent.click(checkButton);

      await waitFor(() => {
        expect(screen.getByText('API Status: Offline')).toBeInTheDocument();
      });

      expect(screen.getByText('✗ Connection failed')).toBeInTheDocument();
      
      const statusScreen = screen.getByText('API Status: Offline').closest('div');
      expect(statusScreen).toHaveClass('red');
    });

    test('displays red status screen when API returns 500', async () => {
      fetch.mockResolvedValueOnce({
        status: 500,
      });

      render(<App />);
      
      const checkButton = screen.getByRole('button', { name: /check status/i });
      fireEvent.click(checkButton);

      await waitFor(() => {
        expect(screen.getByText('API Status: Offline')).toBeInTheDocument();
      });

      const statusScreen = screen.getByText('API Status: Offline').closest('div');
      expect(statusScreen).toHaveClass('red');
    });
  });

  describe('Status Check - Network Error', () => {
    test('displays red status screen when fetch throws error', async () => {
      fetch.mockRejectedValueOnce(new Error('Network error'));

      render(<App />);
      
      const checkButton = screen.getByRole('button', { name: /check status/i });
      fireEvent.click(checkButton);

      await waitFor(() => {
        expect(screen.getByText('API Status: Offline')).toBeInTheDocument();
      });

      expect(screen.getByText('✗ Connection failed')).toBeInTheDocument();
      
      const statusScreen = screen.getByText('API Status: Offline').closest('div');
      expect(statusScreen).toHaveClass('red');
    });
  });

  describe('Back Button Navigation', () => {
    test('returns to welcome screen when back button is clicked from success state', async () => {
      fetch.mockResolvedValueOnce({
        status: 200,
      });

      render(<App />);
      
      // Navigate to status screen
      const checkButton = screen.getByRole('button', { name: /check status/i });
      fireEvent.click(checkButton);

      await waitFor(() => {
        expect(screen.getByText('API Status: Online')).toBeInTheDocument();
      });

      // Click back button
      const backButton = screen.getByRole('button', { name: /back/i });
      fireEvent.click(backButton);

      // Should return to welcome screen
      expect(screen.getByText('Welcome to FastAPI')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /check status/i })).toBeInTheDocument();
    });

    test('returns to welcome screen when back button is clicked from error state', async () => {
      fetch.mockRejectedValueOnce(new Error('Network error'));

      render(<App />);
      
      // Navigate to status screen
      const checkButton = screen.getByRole('button', { name: /check status/i });
      fireEvent.click(checkButton);

      await waitFor(() => {
        expect(screen.getByText('API Status: Offline')).toBeInTheDocument();
      });

      // Click back button
      const backButton = screen.getByRole('button', { name: /back/i });
      fireEvent.click(backButton);

      // Should return to welcome screen
      expect(screen.getByText('Welcome to FastAPI')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /check status/i })).toBeInTheDocument();
    });
  });

  describe('API Integration', () => {
    test('calls correct API endpoint', async () => {
      fetch.mockResolvedValueOnce({
        status: 200,
      });

      render(<App />);
      
      const checkButton = screen.getByRole('button', { name: /check status/i });
      fireEvent.click(checkButton);

      await waitFor(() => {
        expect(fetch).toHaveBeenCalledTimes(1);
      });

      // Verify the correct URL is called (update this to match your actual URL)
      expect(fetch).toHaveBeenCalledWith('http://localhost:8000/ping');
    });
  });

  describe('Multiple Status Checks', () => {
    test('can check status multiple times', async () => {
      // First check - success
      fetch.mockResolvedValueOnce({ status: 200 });

      render(<App />);
      
      const checkButton = screen.getByRole('button', { name: /check status/i });
      fireEvent.click(checkButton);

      await waitFor(() => {
        expect(screen.getByText('API Status: Online')).toBeInTheDocument();
      });

      // Go back
      fireEvent.click(screen.getByRole('button', { name: /back/i }));

      // Second check - failure
      fetch.mockResolvedValueOnce({ status: 500 });
      
      const checkButton2 = screen.getByRole('button', { name: /check status/i });
      fireEvent.click(checkButton2);

      await waitFor(() => {
        expect(screen.getByText('API Status: Offline')).toBeInTheDocument();
      });

      expect(fetch).toHaveBeenCalledTimes(2);
    });
  });
});

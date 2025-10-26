import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import App from './App';

// Basic smoke test for App component
describe('App Component', () => {
  it('renders without crashing', () => {
    render(<App />);
    // Check if some text from App exists
    expect(screen.getByText(/Welcome to FastAPI/i)).toBeInTheDocument(); 
  });
});

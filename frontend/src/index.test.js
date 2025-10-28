/**
 * @jest-environment jsdom
 */

describe('index.js', () => {
  let mockRender;
  let mockCreateRoot;

  beforeAll(() => {
    // Setup DOM
    const root = document.createElement('div');
    root.id = 'root';
    document.body.appendChild(root);
  });

  beforeEach(() => {
    // Clear all mocks
    jest.clearAllMocks();
    jest.resetModules();

    // Create mock functions
    mockRender = jest.fn();
    mockCreateRoot = jest.fn(() => ({
      render: mockRender,
    }));

    // Mock React DOM before requiring index.js
    jest.doMock('react-dom/client', () => ({
      createRoot: mockCreateRoot,
    }));

    // Mock App component
    jest.doMock('./App', () => {
      return function MockApp() {
        return null;
      };
    });

    // Mock reportWebVitals
    jest.doMock('./reportWebVitals', () => ({
      __esModule: true,
      default: jest.fn(),
    }));
  });

  afterEach(() => {
    jest.resetModules();
  });

  test('calls createRoot with root element', () => {
    // Require index.js to execute it
    require('./index.js');

    const rootElement = document.getElementById('root');
    expect(mockCreateRoot).toHaveBeenCalledWith(rootElement);
  });

  test('calls render method', () => {
    require('./index.js');

    expect(mockRender).toHaveBeenCalledTimes(1);
  });

  test('renders without crashing', () => {
    expect(() => {
      require('./index.js');
    }).not.toThrow();
  });
});

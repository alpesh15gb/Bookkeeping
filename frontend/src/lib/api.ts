import axios, { AxiosInstance, InternalAxiosRequestConfig } from "axios";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:8000/api/v1";

export const apiClient: AxiosInstance = axios.create({
  baseURL: API_URL,
  headers: {
    "Content-Type": "application/json",
  },
  withCredentials: false, // Do not send cookies cross-origin (Tauri origin != API origin). Auth uses Bearer tokens.
});

// Memory cache for Access Token (keeps tokens out of localStorage to prevent XSS theft)
let accessTokenMemory: string | null = null;
let refreshTokenMemory: string | null = null;
let activeTenantIdMemory: string | null = null;

export const setAccessToken = (token: string | null) => {
  accessTokenMemory = token;
  if (token) {
    sessionStorage.setItem('_at', token);
  } else {
    sessionStorage.removeItem('_at');
  }
};

export const setRefreshToken = (token: string | null) => {
  refreshTokenMemory = token;
};

export const setTenantId = (tenantId: string | null) => {
  activeTenantIdMemory = tenantId;
  if (tenantId) {
    localStorage.setItem("active_tenant_id", tenantId);
  } else {
    localStorage.removeItem("active_tenant_id");
  }
};

// Retrieve tenant ID from storage on startup
export const getActiveTenantId = (): string | null => {
  if (!activeTenantIdMemory) {
    activeTenantIdMemory = localStorage.getItem("active_tenant_id");
  }
  return activeTenantIdMemory;
};

// Request Interceptor: Attach Auth token and active Tenant headers dynamically
apiClient.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    // 1. Inject Access Token
    if (accessTokenMemory && config.headers) {
      config.headers.Authorization = `Bearer ${accessTokenMemory}`;
    }

    // 2. Inject Tenant Isolation Header
    const tenantId = getActiveTenantId();
    if (tenantId && config.headers) {
      config.headers["X-Tenant-ID"] = tenantId;
    }

    return config;
  },
  (error) => Promise.reject(error)
);

// Response Interceptor: Catch 401s and execute Token Refresh
let isRefreshing = false;
let failedQueue: any[] = [];

const processQueue = (error: any, token: string | null = null) => {
  failedQueue.forEach((prom) => {
    if (error) {
      prom.reject(error);
    } else {
      prom.resolve(token);
    }
  });
  failedQueue = [];
};

apiClient.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config;

    // Trigger token refresh only on 401s (Unauthenticated) when request was not already a retry
    // Skip auth endpoints: 401 on login/register means wrong credentials, not an expired token
    const isAuthEndpoint = originalRequest.url?.includes('/auth/login') || originalRequest.url?.includes('/auth/register');
    if (error.response?.status === 401 && !originalRequest._retry && !isAuthEndpoint) {
      if (isRefreshing) {
        return new Promise((resolve, reject) => {
          failedQueue.push({ resolve, reject });
        })
          .then((token) => {
            originalRequest.headers.Authorization = `Bearer ${token}`;
            return apiClient(originalRequest);
          })
          .catch((err) => Promise.reject(err));
      }

      originalRequest._retry = true;
      isRefreshing = true;

      try {
        // Run token refresh (expects server to return new tokens)
        const refreshResponse = await axios.post(
          `${API_URL}/auth/refresh`,
          { refresh_token: refreshTokenMemory },
          { withCredentials: true }
        );

        const newAccessToken = refreshResponse.data.access_token;
        const newRefreshToken = refreshResponse.data.refresh_token;
        setAccessToken(newAccessToken);
        setRefreshToken(newRefreshToken);

        // Process other queued requests that failed while refreshing
        processQueue(null, newAccessToken);
        isRefreshing = false;

        // Re-run original failed request with new token
        originalRequest.headers.Authorization = `Bearer ${newAccessToken}`;
        return apiClient(originalRequest);
      } catch (refreshError) {
        processQueue(refreshError, null);
        isRefreshing = false;
        // Invalidate token cache and redirect to login on refresh failures
        setAccessToken(null);
        window.location.href = "/login?session_expired=true";
        return Promise.reject(refreshError);
      }
    }

    return Promise.reject(error);
  }
);

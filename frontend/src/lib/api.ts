import axios, { AxiosInstance, InternalAxiosRequestConfig } from "axios";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:8000/api/v1";

export const apiClient: AxiosInstance = axios.create({
  baseURL: API_URL,
  headers: {
    "Content-Type": "application/json",
  },
  withCredentials: false,
});

// Session-storage backed tokens (cleared when tab closes — safer than localStorage)
let accessTokenMemory: string | null = null;
let refreshTokenMemory: string | null = sessionStorage.getItem("_rt");
let activeTenantIdMemory: string | null = null;

export const setAccessToken = (token: string | null) => {
  accessTokenMemory = token;
  if (token) {
    sessionStorage.setItem("_at", token);
  } else {
    sessionStorage.removeItem("_at");
  }
};

export const setRefreshToken = (token: string | null) => {
  refreshTokenMemory = token;
  if (token) {
    sessionStorage.setItem("_rt", token);
  } else {
    sessionStorage.removeItem("_rt");
  }
};

export const setTenantId = (tenantId: string | null) => {
  activeTenantIdMemory = tenantId;
};

export const getActiveTenantId = (): string | null => {
  if (!activeTenantIdMemory) {
    activeTenantIdMemory = localStorage.getItem("active_tenant_id");
  }
  return activeTenantIdMemory;
};

apiClient.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    if (accessTokenMemory && config.headers) {
      config.headers.Authorization = `Bearer ${accessTokenMemory}`;
    }
    const tenantId = getActiveTenantId();
    if (tenantId && config.headers) {
      config.headers["X-Tenant-ID"] = tenantId;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

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

let _sessionExpired = false;

export const getSessionExpired = () => _sessionExpired;
export const clearSessionExpired = () => { _sessionExpired = false; };

apiClient.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config;

    const isAuthEndpoint = originalRequest.url?.includes("/auth/login") || originalRequest.url?.includes("/auth/register");
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
        const refreshResponse = await axios.post(
          `${API_URL}/auth/refresh`,
          { refresh_token: refreshTokenMemory },
          { withCredentials: true }
        );

        const newAccessToken = refreshResponse.data.access_token;
        const newRefreshToken = refreshResponse.data.refresh_token;
        setAccessToken(newAccessToken);
        setRefreshToken(newRefreshToken);

        processQueue(null, newAccessToken);
        isRefreshing = false;

        originalRequest.headers.Authorization = `Bearer ${newAccessToken}`;
        return apiClient(originalRequest);
      } catch (refreshError) {
        processQueue(refreshError, null);
        isRefreshing = false;
        setAccessToken(null);
        setRefreshToken(null);
        _sessionExpired = true;
        // Dispatch custom event instead of hard page reload — lets React handle SPA navigation
        window.dispatchEvent(new CustomEvent("auth:session-expired"));
        return Promise.reject(refreshError);
      }
    }

    return Promise.reject(error);
  }
);

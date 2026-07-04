import axios, { type AxiosRequestConfig } from 'axios'

export interface ApiResponse<T = unknown> {
  code: number
  message: string
  response?: T
}

export interface ApiClientOptions {
  onUnauthorized?: () => void
  onError?: (message: string) => void
}

const apiClient = axios.create({
  timeout: 30000,
  withCredentials: true,
  headers: {
    'request-ajax': true
  }
})

let options: ApiClientOptions = {}

export function configureApiClient(nextOptions: ApiClientOptions) {
  options = nextOptions
}

export async function request<T = unknown>(config: AxiosRequestConfig): Promise<ApiResponse<T>> {
  let data: ApiResponse<T>

  try {
    const requestHeaders: AxiosRequestConfig['headers'] = {
      'request-ajax': true,
      ...config.headers
    }

    if (!isFormData(config.data)) {
      requestHeaders['Content-Type'] = 'application/json'
    }

    const result = await apiClient.request<ApiResponse<T>>({
      ...config,
      headers: requestHeaders
    })
    data = result.data
  } catch (error) {
    const message = resolveErrorMessage(error)
    options.onError?.(message)
    return Promise.reject(error)
  }

  if (data.code === 401 || data.code === 502) {
    options.onUnauthorized?.()
    return Promise.reject(data)
  }

  if (data.code === 500 || data.code === 501) {
    options.onError?.(data.message)
    return Promise.reject(data)
  }

  return data
}

export function post<T = unknown>(url: string, data?: unknown) {
  return request<T>({
    url,
    method: 'post',
    data
  })
}

function isFormData(data: unknown): data is FormData {
  return typeof FormData !== 'undefined' && data instanceof FormData
}

function resolveErrorMessage(error: unknown) {
  if (typeof error === 'object' && error !== null && 'message' in error) {
    return String((error as { message: unknown }).message)
  }

  return '请求失败'
}

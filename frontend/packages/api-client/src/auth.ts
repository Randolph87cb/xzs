import { post, type ApiResponse } from './request'

export interface LoginRequest {
  userName: string
  password: string
  remember: boolean
}

export interface LoginResponse {
  userName: string
  imagePath?: string
}

export function login(payload: LoginRequest): Promise<ApiResponse<LoginResponse>> {
  return post<LoginResponse>('/api/user/login', payload)
}

export function logout(): Promise<ApiResponse<void>> {
  return post<void>('/api/user/logout')
}

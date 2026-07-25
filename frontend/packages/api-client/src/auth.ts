import { post, type ApiResponse } from './request'
import type { StudentUserInfo } from './studentUser'

export interface LoginRequest {
  userName: string
  password: string
  remember: boolean
}

export interface LoginResponse {
  userName: string
  imagePath?: string
}

export function adminLogin(payload: LoginRequest): Promise<ApiResponse<LoginResponse>> {
  return post<LoginResponse>('/api/admin/auth/login', payload)
}

export function adminLogout(): Promise<ApiResponse<void>> {
  return post<void>('/api/admin/auth/logout')
}

export function studentLogin(payload: LoginRequest): Promise<ApiResponse<StudentUserInfo>> {
  return post<StudentUserInfo>('/api/student/auth/login', payload)
}

export function studentLogout(): Promise<ApiResponse<void>> {
  return post<void>('/api/student/auth/logout')
}

import { post, type ApiResponse } from './request'

export interface AdminUserInfo {
  id?: number
  userName: string
  realName?: string
  role?: number
  classId?: number | null
  status?: number
  phone?: string
  imagePath?: string
  createTime?: string
}

export interface AdminUserPageRequest {
  userName?: string
  role?: number
  pageIndex: number
  pageSize: number
}

export interface AdminUserListItem {
  id: number
  userName: string
  realName?: string
  sex?: number
  phone?: string
  createTime?: string
  status?: number
  role?: number
  classId?: number | null
}

export interface AdminPageResponse<T> {
  list: T[]
  total: number
  pageNum: number
  pageSize: number
}

export function getCurrentAdminUser(): Promise<ApiResponse<AdminUserInfo>> {
  return post<AdminUserInfo>('/api/admin/user/current')
}

export function getAdminUserPage(
  request: AdminUserPageRequest
): Promise<ApiResponse<AdminPageResponse<AdminUserListItem>>> {
  return post<AdminPageResponse<AdminUserListItem>>('/api/admin/user/page/list', request)
}

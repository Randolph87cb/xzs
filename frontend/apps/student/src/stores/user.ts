import { defineStore } from 'pinia'
import Cookies from 'js-cookie'
import {
  getCurrentStudentUser,
  studentLogin,
  studentLogout,
  type StudentUserInfo
} from '@xzs/api-client'

interface UserState {
  userName: string
  userInfo: StudentUserInfo | null
  imagePath: string
  hasCheckedSession: boolean
}

let initUserInfoPromise: Promise<void> | null = null
let sessionGeneration = 0

export const useUserStore = defineStore('user', {
  state: (): UserState => ({
    userName: Cookies.get('studentUserName') ?? '',
    userInfo: readUserInfoCookie(),
    imagePath: Cookies.get('studentImagePath') ?? '',
    hasCheckedSession: false
  }),
  getters: {
    hasLocalUserSnapshot: (state) =>
      Boolean(state.userName && state.userInfo?.userName && state.userInfo.userName === state.userName),
    isAuthenticated: (state) =>
      Boolean(state.userName && state.userInfo?.userName && state.userInfo.userName === state.userName),
    displayName: (state) => state.userInfo?.nickName || state.userInfo?.realName || state.userName
  },
  actions: {
    async login(payload: { userName: string; password: string; remember: boolean }) {
      const result = await studentLogin(payload)

      if (result.code !== 1 || !result.response) {
        throw new Error(result.message)
      }

      invalidateInitUserInfoRequest()
      this.setUserInfo(result.response)
      this.setUserName(result.response.userName || payload.userName)
      this.setImagePath(result.response.imagePath ?? '')
      this.hasCheckedSession = true
    },
    async initUserInfo() {
      if (initUserInfoPromise) {
        return initUserInfoPromise
      }

      const requestGeneration = sessionGeneration
      const request = (async () => {
        try {
          const result = await getCurrentStudentUser()

          if (result.code !== 1 || !result.response) {
            throw new Error(result.message || '登录状态校验失败')
          }

          if (requestGeneration !== sessionGeneration) {
            return
          }

          this.setUserInfo(result.response)
          this.setUserName(result.response.userName)
          this.setImagePath(result.response.imagePath ?? '')
        } finally {
          if (requestGeneration === sessionGeneration) {
            this.hasCheckedSession = true
          }
        }
      })()
      initUserInfoPromise = request

      try {
        await request
      } finally {
        if (initUserInfoPromise === request) {
          initUserInfoPromise = null
        }
      }
    },
    async logout() {
      invalidateInitUserInfoRequest()
      try {
        await studentLogout()
      } finally {
        this.clear()
      }
    },
    setUserName(userName: string) {
      this.userName = userName
      Cookies.set('studentUserName', userName, { expires: 30 })
    },
    setUserInfo(userInfo: StudentUserInfo) {
      this.userInfo = userInfo
      Cookies.set('studentUserInfo', JSON.stringify(userInfo), { expires: 30 })
    },
    setImagePath(imagePath: string) {
      this.imagePath = imagePath
      if (imagePath) {
        Cookies.set('studentImagePath', imagePath, { expires: 30 })
      } else {
        Cookies.remove('studentImagePath')
      }
    },
    clear() {
      invalidateInitUserInfoRequest()
      this.userName = ''
      this.userInfo = null
      this.imagePath = ''
      this.hasCheckedSession = true
      Cookies.remove('studentUserName')
      Cookies.remove('studentUserInfo')
      Cookies.remove('studentImagePath')
    }
  }
})

function invalidateInitUserInfoRequest() {
  sessionGeneration += 1
  initUserInfoPromise = null
}

function readUserInfoCookie(): StudentUserInfo | null {
  const rawValue = Cookies.get('studentUserInfo')

  if (!rawValue) {
    return null
  }

  try {
    const parsedValue = JSON.parse(rawValue) as unknown
    if (
      typeof parsedValue !== 'object' ||
      parsedValue === null ||
      !('userName' in parsedValue) ||
      typeof parsedValue.userName !== 'string' ||
      parsedValue.userName.length === 0
    ) {
      return null
    }
    return parsedValue as StudentUserInfo
  } catch {
    return null
  }
}

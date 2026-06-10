export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6 animate-pulse">
      <div className="h-8 w-32 rounded-xl glass-light" />
      <div className="h-40 rounded-2xl glass-light" />
      <div className="h-24 rounded-2xl glass-light" />
    </div>
  )
}
